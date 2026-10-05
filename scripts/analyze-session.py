#!/usr/bin/env python3
"""Analyse a session export or session fixture without reading it by hand.

Decodes GPS, device motion (`motionFramesZlib`, or the `motion` slices of a fixture),
detections and sets, and prints compact views for tuning detection and for labelling jumps,
falls and tricks. Stdlib only.

  sets     FILE                one line per set: GPS quality, laps, motion peaks, last impact
                               before the set end, end reason
  timeline FILE SET [--from S] [--to S]
                               one row per second (S = seconds after set start)
  events   FILE                candidate airtime / impact / spin / GPS events per set
  labels   FILE [--fixture F]  motion + GPS features of every `event` annotation (a fixture
                               carries its own; for a full export pass --fixture)

FILE is a phone Share export (`SessionTransferPackage` JSON) or a session fixture from
`scripts/make-session-fixture.py`.

Device motion is `CMDeviceMotion` in the Watch frame: `userAcceleration` in g with gravity
removed, rotation rate in rad/s, attitude in rad. 25 Hz while riding / unsure, 1 Hz otherwise.
Timestamps are stored to the whole second, so samples inside one second are spread evenly.

Vertical acceleration: gravity in the Watch frame follows from attitude
(x = -sin(roll)·cos(pitch), y = sin(pitch), z = -cos(roll)·cos(pitch)), and
`up = userAcceleration · gravity` is the kinematic acceleration upwards: 0 while riding,
about -1 g in the air (the rope still pulls sideways, so total acceleration does not drop to
zero like in free fall), a positive spike on landing.

Candidate thresholds below are for exploring data, not product thresholds.
"""

from __future__ import annotations

import argparse
import base64
import json
import math
import signal
import struct
import sys
import zlib
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path

ACCURACY_GATE_M = 25.0  # DetectionThresholds.maxHorizontalAccuracyM
LAP_START_RADIUS_M = 50.0  # LapThresholds.startSafeRadiusM
LAP_EXIT_RADIUS_M = 70.0  # LapThresholds.exitRadiusM
LAP_MIN_PATH_M = 200.0  # LapThresholds.minPathBeforeCrossingM

IMPOSSIBLE_STEP_KMH = 60.0  # speed implied by two consecutive positions
AIR_UP_G = -0.6  # vertical acceleration at or below this counts as airborne
AIR_MIN_S = 0.28  # 7 samples at 25 Hz
IMPACT_G = 4.0  # |userAcceleration| spike
SPIN_DEG = 300.0  # net heading change within SPIN_WINDOW_S
SPIN_WINDOW_S = 2.0


def parse_ts(value: str) -> float:
    if value.endswith("Z"):
        value = value[:-1] + "+00:00"
    return datetime.fromisoformat(value).timestamp()


def hms(epoch: float) -> str:
    return datetime.fromtimestamp(epoch, tz=timezone.utc).strftime("%H:%M:%S")


def haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = p2 - p1, math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * 6_371_000.0 * math.asin(min(1.0, math.sqrt(a)))


def percentile(values: list[float], q: float) -> float:
    if not values:
        return float("nan")
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, max(0, round(q * (len(ordered) - 1))))]


def unwrap(angles: list[float]) -> list[float]:
    out, offset = [], 0.0
    for k, angle in enumerate(angles):
        if k:
            step = angle - angles[k - 1]
            if step > math.pi:
                offset -= 2 * math.pi
            elif step < -math.pi:
                offset += 2 * math.pi
        out.append(angle + offset)
    return out


# --- Streams -------------------------------------------------------------------------------


@dataclass
class Fix:
    t: float
    lat: float
    lon: float
    acc: float
    speed: float | None  # m/s; None when CoreLocation had none
    course: float | None


@dataclass
class Motion:
    t: float
    ax: float
    ay: float
    az: float
    rx: float
    ry: float
    rz: float
    pitch: float
    roll: float
    yaw: float

    @property
    def accel(self) -> float:
        return math.sqrt(self.ax * self.ax + self.ay * self.ay + self.az * self.az)

    @property
    def rotation(self) -> float:
        return math.sqrt(self.rx * self.rx + self.ry * self.ry + self.rz * self.rz)

    @property
    def up(self) -> float:
        gx = -math.sin(self.roll) * math.cos(self.pitch)
        gy = math.sin(self.pitch)
        gz = -math.cos(self.roll) * math.cos(self.pitch)
        return self.ax * gx + self.ay * gy + self.az * gz


@dataclass
class RideSet:
    index: int
    start: float
    end: float
    end_reason: str = ""
    laps: list[float] = field(default_factory=list)


@dataclass
class Session:
    manifest: dict
    fixes: list[Fix]  # time order, repeated timestamps dropped
    motion: list[Motion]
    sets: list[RideSet]
    annotations: list[dict]


def decode_motion_frames(blob_b64: str) -> list[dict]:
    """`[UInt32 BE length][raw deflate]` frames → JSONL rows (CompressedJSONLFrames)."""
    raw = base64.b64decode(blob_b64)
    offset, chunks = 0, []
    while offset + 4 <= len(raw):
        (length,) = struct.unpack(">I", raw[offset : offset + 4])
        chunks.append(zlib.decompress(raw[offset + 4 : offset + 4 + length], -15))
        offset += 4 + length
    return [json.loads(line) for line in b"".join(chunks).decode().splitlines() if line.strip()]


def spread_within_second(rows: list[dict]) -> list[Motion]:
    out: list[Motion] = []
    i = 0
    while i < len(rows):
        j = i
        while j < len(rows) and rows[j]["t"] == rows[i]["t"]:
            j += 1
        base = parse_ts(rows[i]["t"])
        for k in range(i, j):
            r = rows[k]
            out.append(Motion(base + (k - i) / (j - i), r["ax"], r["ay"], r["az"], r["rx"], r["ry"], r["rz"],
                              r["p"], r["r"], r["y"]))
        i = j
    out.sort(key=lambda m: m.t)
    return out


def load_fixes(locations: list[dict]) -> list[Fix]:
    by_time: dict[float, Fix] = {}
    for loc in locations:
        t = parse_ts(loc["timestamp"])
        if t in by_time:
            continue
        speed, course = loc.get("speed"), loc.get("course")
        by_time[t] = Fix(t, loc["latitude"], loc["longitude"], loc.get("horizontalAccuracy", -1.0),
                         speed if speed is not None and speed >= 0 else None,
                         course if course is not None and course >= 0 else None)
    return [by_time[t] for t in sorted(by_time)]


def sets_from_detections(detections: list[dict], session_end: float) -> list[RideSet]:
    """Riding windows like SessionStatsBuilder: superseded events drop out, unsure ends a set."""
    superseded = {d["supersedesId"] for d in detections if d.get("supersedesId")}
    live = sorted((d for d in detections if d["id"] not in superseded), key=lambda d: parse_ts(d["timestamp"]))
    sets: list[RideSet] = []
    current: RideSet | None = None
    for d in live:
        t = parse_ts(d["timestamp"])
        if d["code"] == "riding" and current is None:
            current = RideSet(len(sets) + 1, t, t)
        elif d["code"] != "riding" and current is not None:
            current.end, current.end_reason = t, d["detectorId"]
            sets.append(current)
            current = None
    if current is not None:
        current.end, current.end_reason = session_end, "session_end"
        sets.append(current)
    return sets


def lap_crossings(fixes: list[Fix], ride: RideSet) -> list[float]:
    """Rough LapSetTracker: leave the set's first fix, travel, come back inside the start radius."""
    usable = [f for f in fixes if ride.start <= f.t <= ride.end and 0 <= f.acc <= ACCURACY_GATE_M]
    if not usable:
        return []
    origin = last = usable[0]
    left, path, crossings = False, 0.0, []
    for f in usable[1:]:
        path += haversine_m(last.lat, last.lon, f.lat, f.lon)
        last = f
        distance = haversine_m(origin.lat, origin.lon, f.lat, f.lon)
        if distance > LAP_EXIT_RADIUS_M:
            left = True
        elif left and distance <= LAP_START_RADIUS_M and path >= LAP_MIN_PATH_M:
            crossings.append(f.t)
            left, path = False, 0.0
    return crossings


def load(path: Path) -> Session:
    package = json.loads(path.read_text(encoding="utf-8"))
    manifest = package["manifest"]
    if package.get("motionFramesZlib"):
        rows = decode_motion_frames(package["motionFramesZlib"])
    else:
        rows = [r for r in package.get("motion") or [] if "ax" in r]  # fixture slices
    detections = package.get("detections") or package.get("recordedDetections") or []
    fixes = load_fixes(package.get("locations") or [])
    sets = sets_from_detections(detections, parse_ts(manifest.get("endedAt") or manifest["startedAt"]))
    for ride in sets:
        ride.laps = lap_crossings(fixes, ride)
    return Session(manifest, fixes, spread_within_second(rows), sets, package.get("annotations") or [])


# --- Features ------------------------------------------------------------------------------


def window(items: list, start: float, end: float) -> list:
    return [x for x in items if start <= x.t <= end]


def step_kmh(prev: Fix, cur: Fix) -> float:
    dt = cur.t - prev.t
    return haversine_m(prev.lat, prev.lon, cur.lat, cur.lon) / dt * 3.6 if dt > 0 else float("inf")


def air_runs(motion: list[Motion]) -> list[tuple[float, float, float]]:
    """(start, duration, landing peak up) of runs with up <= AIR_UP_G, one-sample dropouts allowed."""
    runs = []
    i = 0
    while i < len(motion):
        if motion[i].up > AIR_UP_G:
            i += 1
            continue
        j = i
        while j + 1 < len(motion) and motion[j + 1].t - motion[j].t < 0.1 and (
            motion[j + 1].up <= AIR_UP_G
            or (j + 2 < len(motion) and motion[j + 2].up <= AIR_UP_G and motion[j + 2].t - motion[j].t < 0.1)
        ):
            j += 1
        duration = motion[j].t - motion[i].t + 0.04
        if duration >= AIR_MIN_S:
            landing = max((m.up for m in motion[j + 1 : j + 10]), default=0.0)
            runs.append((motion[i].t, duration, landing))
        i = j + 1
    return runs


def net_turns(motion: list[Motion]) -> list[tuple[float, float]]:
    """(t, net heading change in degrees over the SPIN_WINDOW_S ending at t).

    Net, not summed: a spin or a tumble keeps turning one way, jitter and carving cancel out.
    """
    if len(motion) < 2:
        return []
    yaw = unwrap([m.yaw for m in motion])
    out, j = [], 0
    for i in range(len(motion)):
        while motion[i].t - motion[j].t > SPIN_WINDOW_S:
            j += 1
        if motion[i].t - motion[j].t >= SPIN_WINDOW_S * 0.9:
            out.append((motion[i].t, math.degrees(yaw[i] - yaw[j])))
    return out


@dataclass
class Event:
    t: float
    kind: str
    detail: str


def motion_events(motion: list[Motion]) -> list[Event]:
    events = [Event(t, "air", f"{d:.2f}s up<={AIR_UP_G}g, landing {land:+.1f}g") for t, d, land in air_runs(motion)]
    burst: list[Motion] = []
    for m in motion + [Motion(math.inf, 0, 0, 0, 0, 0, 0, 0, 0, 0)]:
        if burst and m.t - burst[-1].t > 1.0:
            peak = max(burst, key=lambda x: x.accel)
            rot = max(x.rotation for x in window(motion, burst[0].t - 0.5, burst[-1].t + 0.5))
            events.append(Event(burst[0].t, "impact", f"peak {peak.accel:.1f}g, rot up to {rot:.1f}rad/s"))
            burst = []
        if m.accel >= IMPACT_G:
            burst.append(m)
    last = -10.0
    for t, turn in net_turns(motion):
        if abs(turn) >= SPIN_DEG and t - last > SPIN_WINDOW_S:
            events.append(Event(t - SPIN_WINDOW_S, "spin", f"{turn:+.0f}deg in {SPIN_WINDOW_S:.0f}s"))
            last = t
    return events


def gps_events(fixes: list[Fix]) -> list[Event]:
    events = []
    for prev, cur in zip(fixes, fixes[1:]):
        if cur.t - prev.t >= 3:
            events.append(Event(prev.t, "gps_gap", f"{cur.t - prev.t:.0f}s without a fix"))
        kmh = step_kmh(prev, cur)
        if kmh >= IMPOSSIBLE_STEP_KMH and haversine_m(prev.lat, prev.lon, cur.lat, cur.lon) > 15:
            events.append(Event(cur.t, "gps_jump", f"step {kmh:.0f}km/h acc={cur.acc:.0f}m"))
        if cur.acc > ACCURACY_GATE_M and cur.speed is not None and prev.speed == cur.speed:
            events.append(Event(cur.t, "gps_coast", f"speed {cur.speed * 3.6:.1f}km/h repeated at acc={cur.acc:.0f}m"))
    return events


def mean_speed_kmh(fixes: list[Fix], start: float, end: float) -> float | None:
    speeds = [f.speed for f in window(fixes, start, end) if f.speed is not None and 0 <= f.acc <= ACCURACY_GATE_M]
    return sum(speeds) / len(speeds) * 3.6 if speeds else None


def fmt(value: float | None, spec: str = "4.0f") -> str:
    return format(value, spec) if value is not None else "-".rjust(int(spec.split(".")[0]))


# --- Commands ------------------------------------------------------------------------------


def cmd_sets(session: Session, _args: argparse.Namespace) -> None:
    m = session.manifest
    print(f"park={m.get('parkId')} start={m['startedAt']} fixes={len(session.fixes)} motion={len(session.motion)}")
    print("set start    end      dur laps fixes acc50 acc90 >gate jumps coast  maxG maxRot  lastImpact  end")
    for ride in session.sets:
        fixes = window(session.fixes, ride.start - 1, ride.end + 1)
        accs = [f.acc for f in fixes if f.acc >= 0]
        gps = gps_events(fixes)
        motion = window(session.motion, ride.start, ride.end)
        impacts = [e.t for e in motion_events(window(session.motion, ride.end - 30, ride.end)) if e.kind == "impact"]
        last_impact = f"{hms(impacts[-1])} {impacts[-1] - ride.end:+3.0f}s" if impacts else "-".ljust(13)
        print(
            f"{ride.index:>3} {hms(ride.start)} {hms(ride.end)} {ride.end - ride.start:>4.0f} {len(ride.laps):>4} "
            f"{len(fixes):>5} {percentile(accs, .5):>5.1f} {percentile(accs, .9):>5.1f} "
            f"{sum(a > ACCURACY_GATE_M for a in accs):>5} {sum(e.kind == 'gps_jump' for e in gps):>5} "
            f"{sum(e.kind == 'gps_coast' for e in gps):>5} {max((x.accel for x in motion), default=0):>5.1f} "
            f"{max((x.rotation for x in motion), default=0):>6.1f}  {last_impact} {ride.end_reason}"
        )


def cmd_timeline(session: Session, args: argparse.Namespace) -> None:
    ride = next(r for r in session.sets if r.index == args.set)
    start = ride.start + (args.from_s if args.from_s is not None else -5)
    end = ride.start + args.to_s if args.to_s is not None else ride.end + 15
    fixes = window(session.fixes, start - 2, end)
    by_second = {int(f.t): f for f in fixes}
    steps = {int(cur.t): step_kmh(prev, cur) for prev, cur in zip(fixes, fixes[1:])}
    laps = {int(t) for t in ride.laps}
    motion = window(session.motion, start, end + 1)
    airborne = {int(t + k * 0.04) for t, duration, _ in air_runs(motion) for k in range(round(duration / 0.04))}
    print(f"set {ride.index} {hms(ride.start)}-{hms(ride.end)} end={ride.end_reason}")
    print("time      +s  kmh step  acc  n  maxG  minUp  maxUp maxRot  dYaw  flags")
    for second in range(int(start), int(end) + 1):
        fix, ms = by_second.get(second), [m for m in motion if second <= m.t < second + 1]
        yaw = unwrap([m.yaw for m in ms])
        ups = [m.up for m in ms]
        flags = []
        if fix is None:
            flags.append("noFix")
        elif fix.acc > ACCURACY_GATE_M:
            flags.append("acc")
        if steps.get(second, 0) >= IMPOSSIBLE_STEP_KMH:
            flags.append("jump")
        if second in airborne:
            flags.append("AIR")
        if ms and max(m.accel for m in ms) >= IMPACT_G:
            flags.append("IMPACT")
        if second in laps:
            flags.append("LAP")
        print(
            f"{hms(second)} {second - ride.start:>4.0f} {fmt(fix.speed * 3.6 if fix and fix.speed is not None else None)} "
            f"{fmt(steps.get(second) if second in steps and steps[second] != float('inf') else None)} "
            f"{fmt(fix.acc if fix else None)} {len(ms):>2} {max((m.accel for m in ms), default=0):5.1f} "
            f"{min(ups, default=0):+6.1f} {max(ups, default=0):+6.1f} {max((m.rotation for m in ms), default=0):6.1f} "
            f"{math.degrees(yaw[-1] - yaw[0]) if len(yaw) > 1 else 0:+5.0f}  {' '.join(flags)}"
        )


def cmd_events(session: Session, _args: argparse.Namespace) -> None:
    for ride in session.sets:
        start, end = ride.start - 2, ride.end + 20
        events = gps_events(window(session.fixes, start, end)) + motion_events(window(session.motion, start, end))
        laps = ", ".join(f"+{t - ride.start:.0f}s" for t in ride.laps) or "-"
        print(f"set {ride.index} {hms(ride.start)}-{hms(ride.end)} end={ride.end_reason} laps at {laps}")
        for e in sorted(events, key=lambda e: e.t):
            print(f"   {hms(e.t)} +{e.t - ride.start:>5.1f}s {e.kind:<8} {e.detail}")


def cmd_labels(session: Session, args: argparse.Namespace) -> None:
    annotations = session.annotations
    if args.fixture:
        annotations = json.loads(args.fixture.read_text(encoding="utf-8")).get("annotations", [])
    print("label        obstacle id                    maxG maxRot  air(s) land  spin°  kmh before→after  set end - start")
    for a in annotations:
        if a.get("kind") != "event":
            continue
        start, end = parse_ts(a["start"]), parse_ts(a["end"])
        motion = window(session.motion, start - 0.5, end + 0.5)
        runs = air_runs(motion)
        longest = max(runs, key=lambda r: r[1], default=None)
        turns = [abs(turn) for _, turn in net_turns(window(session.motion, start - 0.5, end + 2))]
        ride = next((r for r in session.sets if r.start - 5 <= start <= r.end + 30), None)
        before = mean_speed_kmh(session.fixes, start - 3, start)
        after = mean_speed_kmh(session.fixes, end + 1, end + 4)
        set_end = f"{ride.end - start:+.0f}s" if ride else "-"
        print(
            f"{a.get('label', '?'):<12} {a.get('obstacle', '-'):<8} {a['id']:<21} "
            f"{max((m.accel for m in motion), default=0):4.1f} {max((m.rotation for m in motion), default=0):6.1f} "
            f"{longest[1] if longest else 0:7.2f} {longest[2] if longest else 0:+5.1f} {max(turns, default=0):6.0f}  "
            f"{fmt(before)} → {fmt(after)}       {set_end}"
        )


def main() -> int:
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)  # quiet when piped into head
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("sets", "events"):
        sub.add_parser(name).add_argument("file", type=Path)
    p = sub.add_parser("timeline")
    p.add_argument("file", type=Path)
    p.add_argument("set", type=int)
    p.add_argument("--from", dest="from_s", type=float, help="seconds after set start (default -5)")
    p.add_argument("--to", dest="to_s", type=float, help="seconds after set start (default end +15)")
    p = sub.add_parser("labels")
    p.add_argument("file", type=Path)
    p.add_argument("--fixture", type=Path, help="fixture whose annotations label FILE")
    args = parser.parse_args()

    commands = {"sets": cmd_sets, "timeline": cmd_timeline, "events": cmd_events, "labels": cmd_labels}
    commands[args.command](load(args.file), args)
    return 0


if __name__ == "__main__":
    sys.exit(main())
