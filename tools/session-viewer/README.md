# Session viewer

Dev tool: load session folder JSONL or phone export JSON, scrub a time window + playhead, plot detections / speed / track / GPS accuracy / battery. Realtime play/pause (button or Space).

```bash
# needs Node 20+ (nvm use 24)
npm i
npm run dev
```

Open folder with `manifest.json`, `detections.jsonl` (or legacy `assumptions.jsonl`), `location-*.jsonl`, optional `battery-*.jsonl`. Or open Share export `.json`.

Top summary: distance, sets, laps, peak/avg speed, riding time (derived offline, mirrors Core). Timeline: green = riding, blue = inactive, grey = unsure; yellow verticals = lap crossings. Track rings = lap start anchors. Battery panel plots level × 100 (%); charging/full samples get markers. Playhead scrubber + chart/track click show time, speed, location, and battery.
