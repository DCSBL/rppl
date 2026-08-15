# Session viewer

Dev tool: load session folder JSONL or phone export JSON, scrub a time window + playhead, plot relative track (colored by detection) + speed/accuracy/detections. Realtime play/pause (button or Space).

```bash
# needs Node 20+ (nvm use 24)
npm i
npm run dev
```

Open folder with `manifest.json`, `detections.jsonl` (or legacy `assumptions.jsonl`), `location-*.jsonl`. Or open Share export `.json`.

Track colors: green = riding, blue = paused, grey = unsure. Yellow rings = assumed lap start anchors (derived). Playhead scrubber + chart/track click show time, speed, and location.
