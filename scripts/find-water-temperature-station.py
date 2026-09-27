#!/usr/bin/env python3
"""Find the nearest Rijkswaterstaat surface-water temperature station that still reports.

Used to fill a park's `water_temperature: { provider: rws_nl, station_id: ... }` (see
Docs/Parks.md and the `park-data-collection` skill). RWS publishes many "zwemwater" stations
that stopped reporting a decade or more ago, so picking the geographically nearest one is not
enough — this walks outward by distance and checks each candidate's latest observation via the
WaterWebServices ONLINEWAARNEMINGENSERVICES API until it finds one with a recent reading.

Usage:
    scripts/find-water-temperature-station.py <lat> <lon> [--max-age-days N] [--candidates N]

Example:
    scripts/find-water-temperature-station.py 52.3581295 5.2152087
"""

from __future__ import annotations

import argparse
import json
import math
import sys
import urllib.request
from datetime import datetime, timezone

CATALOG_URL = "https://ddapi20-waterwebservices.rijkswaterstaat.nl/METADATASERVICES/OphalenCatalogus"
OBSERVATIONS_URL = (
    "https://ddapi20-waterwebservices.rijkswaterstaat.nl/ONLINEWAARNEMINGENSERVICES/OphalenLaatsteWaarnemingen"
)


def post_json(url: str, body: dict, timeout: float = 30) -> dict:
    data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.load(resp)


def haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    r = 6371.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlmb = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dlmb / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def water_temperature_locations(catalog: dict) -> list[dict]:
    """Locations (by Locatie_MessageID) that have a Compartiment=OW / Grootheid=T series."""
    temp_meta_ids = {
        m["AquoMetadata_MessageID"]
        for m in catalog["AquoMetadataLijst"]
        if m.get("Compartiment", {}).get("Code") == "OW" and m.get("Grootheid", {}).get("Code") == "T"
    }
    temp_loc_ids = {
        link["Locatie_MessageID"]
        for link in catalog["AquoMetadataLocatieLijst"]
        if link["AquoMetaData_MessageID"] in temp_meta_ids
    }
    locs_by_id = {loc["Locatie_MessageID"]: loc for loc in catalog["LocatieLijst"]}
    return [locs_by_id[i] for i in temp_loc_ids if i in locs_by_id and "Lat" in locs_by_id[i]]


def latest_observation(station_code: str) -> tuple[str, float] | None:
    """Returns (ISO timestamp, celsius) for a station's most recent OW/T reading, or None."""
    body = {
        "AquoPlusWaarnemingMetadataLijst": [
            {"AquoMetadata": {"Compartiment": {"Code": "OW"}, "Grootheid": {"Code": "T"}}}
        ],
        "LocatieLijst": [{"Code": station_code}],
    }
    try:
        result = post_json(OBSERVATIONS_URL, body)
    except Exception:
        return None
    best: tuple[str, float] | None = None
    for obs in result.get("WaarnemingenLijst") or []:
        for meting in obs.get("MetingenLijst", []):
            ts = meting.get("Tijdstip")
            value = meting.get("Meetwaarde", {}).get("Waarde_Numeriek")
            if ts is None or value is None:
                continue
            if best is None or ts > best[0]:
                best = (ts, value)
    return best


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("lat", type=float)
    parser.add_argument("lon", type=float)
    parser.add_argument(
        "--max-age-days",
        type=float,
        default=90,
        help="Only accept a station whose latest reading is at most this many days old (default: 90).",
    )
    parser.add_argument(
        "--candidates",
        type=int,
        default=30,
        help="How many of the nearest stations to check before giving up (default: 30).",
    )
    args = parser.parse_args()

    print(f"Fetching RWS station catalog...", file=sys.stderr)
    catalog = post_json(
        CATALOG_URL,
        {"CatalogusFilter": {"Compartimenten": True, "Grootheden": True, "Locaties": True}},
    )
    locations = water_temperature_locations(catalog)
    locations.sort(key=lambda loc: haversine_km(args.lat, args.lon, loc["Lat"], loc["Lon"]))

    now = datetime.now(timezone.utc)
    checked = 0
    for loc in locations:
        if checked >= args.candidates:
            break
        checked += 1
        dist_km = haversine_km(args.lat, args.lon, loc["Lat"], loc["Lon"])
        code = loc["Code"]
        obs = latest_observation(code)
        if obs is None:
            print(f"  {code:35s} {dist_km:5.1f} km  no observations", file=sys.stderr)
            continue
        ts, celsius = obs
        age_days = (now - datetime.fromisoformat(ts)).total_seconds() / 86400
        status = "OK" if age_days <= args.max_age_days else "stale"
        print(f"  {code:35s} {dist_km:5.1f} km  last={ts}  {celsius}C  ({status})", file=sys.stderr)
        if age_days <= args.max_age_days:
            print()
            print(f"station_id: {code}")
            print(f"name: {loc.get('Naam', code)}")
            print(f"distance_km: {dist_km:.1f}")
            print(f"last_reading: {ts} ({celsius} C)")
            print()
            print("YAML snippet:")
            print(f"water_temperature: {{ provider: rws_nl, station_id: {code} }}")
            return 0

    print(
        f"\nNo station within {args.candidates} nearest candidates reported in the last "
        f"{args.max_age_days:.0f} days. Try --candidates or --max-age-days with a higher value, "
        "or omit water_temperature for this park.",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
