"""Propose cable routes from the towers confirmed in the app's tower review.

The reviewer puts each confirmed tower on its wheel, where the cable wraps around it, so the
wheels are the bends of the cable. This groups a park's wheels into cables and orders each one:

- a full-size loop is 4-6 towers on a convex polygon (towers stand outside the loop), 350-1300 m
  around, every bend 30-95 degrees (up to 110 at a cost: the wheels
  are placed by eye),
- a 2.0 cable is two towers 100-240 m apart, and two labels within 15 m count as one tower,
- the grouping that leaves the fewest towers unused wins, then loops before 2.0 pairs, then the
  bends closest to 90 degrees. Two loops may share a tower but not overlap.

The travel direction is not visible on the image: loops are written counter-clockwise (most traced
parks run that way) and marked so in the report. Run with --check to score the proposals against
the parks that already have traced cables.

    python3 routes_from_labels.py tower-labels.json --parks <Parks dir> [--check | --write]
"""

import argparse
import itertools
import json
import math
import os

import yaml
from shapely.geometry import Polygon

M_PER_DEG = 111_320.0
LOOP_SIZES = (4, 5, 6)
LOOP_LENGTH = (350.0, 1300.0)
MAX_TURN = 110.0  # traced bends stop at 94; the review's wheels are a few metres off
SAME_TOWER_M = 15.0
STRAIGHT_LENGTH = (100.0, 240.0)
MIN_TURN = 30.0
MIN_SEGMENT = 20.0


def local(points, origin):
    lat0, lon0 = origin
    k = math.cos(math.radians(lat0))
    return [((lon - lon0) * M_PER_DEG * k, (lat - lat0) * M_PER_DEG) for lat, lon in points]


def back(xy, origin):
    lat0, lon0 = origin
    k = math.cos(math.radians(lat0))
    return [(lat0 + y / M_PER_DEG, lon0 + x / (M_PER_DEG * k)) for x, y in xy]


def hull_order(xy):
    """Indices in counter-clockwise order if every point is a hull vertex, else None."""
    cx = sum(p[0] for p in xy) / len(xy)
    cy = sum(p[1] for p in xy) / len(xy)
    order = sorted(range(len(xy)), key=lambda i: math.atan2(xy[i][1] - cy, xy[i][0] - cx))
    n = len(order)
    for k in range(n):
        a, b, c = (xy[order[(k + j) % n]] for j in range(3))
        if (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0]) <= 0:
            return None
    return order


def turns(poly):
    n = len(poly)
    out = []
    for k in range(n):
        a, b, c = poly[k - 1], poly[k], poly[(k + 1) % n]
        h1 = math.atan2(b[1] - a[1], b[0] - a[0])
        h2 = math.atan2(c[1] - b[1], c[0] - b[0])
        out.append(abs(math.degrees((h2 - h1 + math.pi) % (2 * math.pi) - math.pi)))
    return out


def perimeter(poly):
    return sum(math.dist(poly[k - 1], poly[k]) for k in range(len(poly)))


def loop_cost(xy, idx):
    """Shape cost of a loop through these towers (lower is better) and its order, or None."""
    pts = [xy[i] for i in idx]
    order = hull_order(pts)
    if order is None:
        return None
    poly = [pts[i] for i in order]
    length = perimeter(poly)
    if not LOOP_LENGTH[0] <= length <= LOOP_LENGTH[1]:
        return None
    t = turns(poly)
    if max(t) > MAX_TURN or min(t) < MIN_TURN:
        return None
    if min(math.dist(poly[k - 1], poly[k]) for k in range(len(poly))) < MIN_SEGMENT:
        return None
    sharp = sum(max(0.0, a - 95.0) for a in t) / 20.0
    return sum((a - 90.0) ** 2 for a in t) / len(t) / 2000.0 + sharp, [idx[i] for i in order]


def apart(poly_a, poly_b):
    """True when two loops do not overlap (they may share towers)."""
    a, b = Polygon(poly_a), Polygon(poly_b)
    return a.intersection(b).area < 1.0


def best_grouping(xy):
    """Pick loops and 2.0 pairs that explain the most towers.

    Cost: 1 per tower left out, 0.6 per 2.0 pair, 0.2 per loop plus its shape cost. Two loops may
    share up to two towers (two cables on one tower) but must not overlap; a 2.0 pair never shares.
    """
    n = len(xy)
    loops = []
    for size in LOOP_SIZES:
        for idx in itertools.combinations(range(n), size):
            found = loop_cost(xy, idx)
            if found:
                loops.append((0.2 + found[0], found[1]))
    loops.sort()
    pairs = [(0.6, [i, j]) for i, j in itertools.combinations(range(n), 2)
             if STRAIGHT_LENGTH[0] <= math.dist(xy[i], xy[j]) <= STRAIGHT_LENGTH[1]]
    best = (float(n), [])

    def fits(chosen, cable):
        for other in chosen:
            shared = set(other) & set(cable)
            if len(cable) == 2 or len(other) == 2:
                if shared:
                    return False
                continue
            if len(shared) > 2 or not apart([xy[i] for i in other], [xy[i] for i in cable]):
                return False
        return True

    def search(start, chosen, cost):
        nonlocal best
        covered = set().union(*chosen) if chosen else set()
        total = cost + (n - len(covered))
        if total < best[0]:
            best = (total, list(chosen))
        if len(chosen) == 4:
            return
        options = loops + pairs
        for k in range(start, len(options)):
            c, cable = options[k]
            if set(cable) <= covered or not fits(chosen, cable):
                continue
            search(k + 1, chosen + [cable], cost + c)

    search(0, [], 0.0)
    chosen = best[1]
    covered = set().union(*chosen) if chosen else set()
    return chosen, n - len(covered)


def towers_of(labels):
    """The confirmed wheels; two labels within 15 m are one tower labelled twice."""
    towers = []
    for label in labels:
        if label.get("verdict") not in ("tower", "mast"):
            continue
        point = (label["coordinate"]["lat"], label["coordinate"]["lon"])
        if all(math.dist(*local([point, other], point)) > SAME_TOWER_M for other in towers):
            towers.append(point)
    return towers


def traced_cables(park):
    out = []
    for cable in park.get("cables") or []:
        pts = cable.get("points") or []
        if len(pts) >= 2:
            out.append((cable.get("direction"), [(p["lat"], p["lon"]) for p in pts]))
    return out


def propose(towers):
    origin = towers[0]
    xy = local(towers, origin)
    groups, unused = best_grouping(xy)
    cables = []
    for g in sorted(groups, key=len, reverse=True):
        cables.append({"direction": "2.0" if len(g) == 2 else "ccw",
                       "points": [towers[i] for i in g],
                       "length_m": round(perimeter([xy[i] for i in g]) if len(g) > 2 else math.dist(xy[g[0]], xy[g[1]]))})
    return cables, unused


def compare(proposed, traced):
    """Mean distance from each traced bend to the nearest proposed bend of the matching cable."""
    rows = []
    for direction, pts in traced:
        kind = "2.0" if direction == "2.0" else "loop"
        origin = pts[0]
        txy = local(pts, origin)
        best = None
        for cable in proposed:
            if (cable["direction"] == "2.0") != (kind == "2.0"):
                continue
            pxy = local(cable["points"], origin)
            d = [min(math.dist(t, p) for p in pxy) for t in txy]
            score = sum(d) / len(d)
            if best is None or score < best[0]:
                best = (score, max(d), len(pxy), len(txy))
        rows.append((kind, best))
    return rows


def cable_lines(cable, indent="    "):
    lines = [f'{indent}direction: {json.dumps(cable["direction"]) if cable["direction"] == "2.0" else cable["direction"]}',
             f'{indent}length_m: {cable["length_m"]}', f"{indent}points:"]
    for lat, lon in cable["points"]:
        lines += [f"{indent}  - lat: {lat:.7f}", f"{indent}    lon: {lon:.7f}"]
    return lines


def write_park(path, cables, today, note):
    """Put the proposed cables into a park YAML as text, keeping everything else as it is.

    A cable entry without points gets the first proposal of its kind (its name and description
    stay); proposals left over become new entries. Returns False when nothing was written.
    """
    lines = open(path).read().split("\n")
    loops = [c for c in cables if c["direction"] != "2.0"]
    straights = [c for c in cables if c["direction"] == "2.0"]
    if "cables:" in lines:
        top = lines.index("cables:")
        end = top + 1
        while end < len(lines) and (lines[end].startswith(" ") or lines[end] == "" and end + 1 < len(lines) and lines[end + 1].startswith(" ")):
            end += 1
        entries = [i for i in range(top + 1, end) if lines[i].startswith("  - ")]
        out = lines[:top + 1]
        for k, first in enumerate(entries):
            last = entries[k + 1] if k + 1 < len(entries) else end
            block = lines[first:last]
            if any(l.strip().startswith("points:") for l in block):
                out += block
                continue
            is_straight = any(l.strip() == 'direction: "2.0"' for l in block)
            pool = straights if is_straight else loops
            if not pool:
                out += block
                continue
            found = pool.pop(0)
            kept = [l for l in block[1:] if not l.strip().startswith(("direction:", "length_m:"))]
            out += [block[0]] + cable_lines(found) + kept
        tail = lines[end:]
    else:
        anchor = lines.index("opening:") if "opening:" in lines else len(lines)
        out = lines[:anchor] + ["cables:"]
        tail = [""] + lines[anchor:]
    for found in loops + straights:
        out += [f'  - name: {"Training cable" if found["direction"] == "2.0" else "Cable"}'] + cable_lines(found)
    lines = out + tail
    lines = [f"updated_at: {today}" if l.startswith("updated_at:") else l for l in lines]
    h = lines.index("history:") + 1
    while h < len(lines) and lines[h].startswith(" "):
        h += 1
    lines[h:h] = [f"  - date: {today}", f"    description: {note}"]
    open(path, "w").write("\n".join(lines))
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("labels")
    ap.add_argument("--parks", required=True)
    ap.add_argument("--check", action="store_true", help="score against parks that have traced cables")
    ap.add_argument("--out", help="write the proposals as JSON")
    ap.add_argument("--write", action="store_true",
                    help="fill the untraced parks whose towers all fit (no tower left over, at least one loop)")
    ap.add_argument("--today", default=__import__("datetime").date.today().isoformat())
    args = ap.parse_args()
    labels = json.load(open(args.labels))["parks"]
    report = {}
    for slug, labs in sorted(labels.items()):
        towers = towers_of(labs)
        path = os.path.join(args.parks, slug + ".yaml")
        if len(towers) < 2 or not os.path.exists(path):
            continue
        park = yaml.safe_load(open(path))
        traced = traced_cables(park)
        if args.check != bool(traced):
            continue
        cables, unused = propose(towers)
        report[slug] = {"towers": len(towers), "unused": unused, "cables": cables}
        line = f"{slug}: {len(towers)} towers -> " + ", ".join(
            f"{c['direction']} {len(c['points'])} pts {c['length_m']} m" for c in cables) + (f", {unused} unused" if unused else "")
        if args.check:
            for kind, best in compare(cables, traced):
                line += f" | traced {kind}: " + ("not proposed" if best is None else f"mean {best[0]:.0f} m, max {best[1]:.0f} m ({best[2]} vs {best[3]} pts)")
        if args.write and not args.check and not unused and any(c["direction"] != "2.0" for c in cables):
            write_park(path, cables, args.today, "Cable route from the towers confirmed in the tower review "
                       "(direction assumed ccw)")
            line += "  [written]"
        print(line)
    if args.out:
        json.dump(report, open(args.out, "w"), indent=1)


if __name__ == "__main__":
    main()
