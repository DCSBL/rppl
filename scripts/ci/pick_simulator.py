#!/usr/bin/env python3
"""Print the UDID of the simulator called NAME, creating it when the runner image lacks it.

Usage: pick_simulator.py "iPhone SE (3rd generation)"
"""
import json
import subprocess
import sys


def simctl(*args: str) -> str:
    return subprocess.run(["xcrun", "simctl", *args], check=True, capture_output=True, text=True).stdout


def find_device(devices: dict, name: str) -> str | None:
    """UDID of an available device called `name`, newest runtime first."""
    for runtime, entries in sorted(devices.items(), reverse=True):
        for d in entries:
            if d["name"] == name and d["isAvailable"]:
                return d["udid"]
    return None


def latest_runtime(runtimes: list[dict], platform: str) -> str:
    candidates = [r for r in runtimes if r["isAvailable"] and r["platform"] == platform]
    if not candidates:
        sys.exit(f"no available {platform} runtime")
    return max(candidates, key=lambda r: [int(p) for p in r["version"].split(".")])["identifier"]


def device_type(types: list[dict], name: str) -> dict:
    for t in types:
        if t["name"] == name:
            return t
    sys.exit(f"unknown device type {name!r}; known: " + ", ".join(t["name"] for t in types))


def main(name: str) -> str:
    found = find_device(json.loads(simctl("list", "devices", "available", "-j"))["devices"], name)
    if found:
        return found
    dtype = device_type(json.loads(simctl("list", "devicetypes", "-j"))["devicetypes"], name)
    platform = "watchOS" if "Watch" in name else "iOS"
    runtime = latest_runtime(json.loads(simctl("list", "runtimes", "-j"))["runtimes"], platform)
    return simctl("create", name, dtype["identifier"], runtime).strip()


if __name__ == "__main__":
    print(main(sys.argv[1]))
