# Session fixtures

Real park-day sessions with hand-written ground truth. `SessionFixtureTests` runs every
fixture listed in `SessionFixture.names` against its annotations, so a field report becomes a
regression test by adding a fixture and annotating what really happened.

## Make one

```bash
python3 scripts/make-session-fixture.py ~/Downloads/rppl_…json park-yyyy-mm-dd \
  --description "Park, length, what went right and wrong"
```

The script keeps the manifest (tester id replaced), the detections the Watch wrote live
(`recordedDetections`) and the locations **in on-disk order** — the Watch appends fixes as they
arrive, so repeated and late fixes stay where they happened. An export that carries every
stream twice is collapsed to one copy (`exportWasDoubled`). Re-running keeps existing
annotations.

Then write `annotations` by hand and add the name to `SessionFixture.names`.

## Annotations

Every annotation has `id`, `kind`, `verdict` and `note`. `verdict` records what the recording or
the live Watch did — `good`, `bad` or `missing` — so a reader sees at a glance which parts are
the examples to learn from. The tests check the *correct* behaviour for every verdict.

| `kind` | Fields | Test |
|--------|--------|------|
| `set` | `start`, optional `end`, `toleranceSeconds` (default 3); optional `liveStart` / `liveEnd` for what the Watch showed | Time-ordered replay has exactly one set per annotation, starting (and ending) within tolerance, and no extra sets. |
| `badFix` | `at` | A fix worse than the 25 m accuracy gate at `at` never reaches the set's map track. |
| `lateDelivery` | `start`, `end`, `arrivedAfter` | Replayed in arrival order, no `ride_enter` goes back in time or lands in the window; `LocationFixSequencer` drops every fix of the window recorded after `arrivedAfter`. |
| `noGps` | `start`, `end` | No usable fix in the window and no set invented there — a recording gap, not a detection bug. |

Times are ISO 8601 UTC. Ground truth comes from the rider and from reading the raw fixes; when
unsure, leave a field out rather than guess.

## Fixtures

- `downunder-2026-09-30` — Cable Park Down Under, ~2 h, 11 sets. Sets 1-9 clean. Set 4 has one
  216 m network fix. Sets 10-11 broken live: good fixes were held back behind HealthKit route
  inserts (fixed in the Watch location callback) while poor fixes went straight to detection. No
  usable GPS after 14:45:13Z although the rider kept riding until ~14:58Z. The phone had imported
  the transfer twice.
