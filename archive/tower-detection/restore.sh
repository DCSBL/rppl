#!/bin/bash
# Puts the parked tower detection back where it was (see README.md). Run from the repo root:
#   archive/tower-detection/restore.sh
set -euo pipefail
A=archive/tower-detection
cd "$(git rev-parse --show-toplevel)"
[ -d "$A/core" ] || { echo "Already restored or archive missing"; exit 1; }

git apply -R "$A/app-wiring.patch"   # debug keys, toggles and the trace-map button
git mv "$A/app/TowerReview" Rppl/Parks/TowerReview
git mv "$A/app/CableDetectionRunner.swift" Rppl/Parks/Editor/CableDetectionRunner.swift
git mv "$A/core/Sources/CableDetection" RpplCore/Sources/RpplCore/CableDetection
for f in "$A"/core/Resources/*.weights; do git mv "$f" RpplCore/Sources/RpplCore/Resources/; done
for f in "$A"/core/Tests/*.swift; do git mv "$f" RpplCore/Tests/RpplCoreTests/; done
git mv "$A/cable-tracer" tools/cable-tracer
echo "Restored. Add 'tools/cable-tracer/.build/' to .gitignore, then build; the Swift port was last compiled by CI at 133417d."
