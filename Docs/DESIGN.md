# System design

How Watch, iPhone, and `WakeTrackerCore` fit together. Library internals (DetectionEngine UML, store types): [../WakeTrackerCore/DESIGN.md](../WakeTrackerCore/DESIGN.md). Product lock: [../README.md](../README.md).

## Layers

```mermaid
flowchart TB
  subgraph watch [WakeTrackerWatch]
    WSC[WatchSessionController]
    Intent[StartCableParkSessionIntent]
  end
  subgraph phone [wake-tracker iOS]
    PCS[PhoneConnectivityService]
    UI[ContentView session list map export]
  end
  subgraph core [WakeTrackerCore]
    Engine[DetectionEngine]
    Codes[DetectionCodes]
    Store[SessionFileStore]
    Sync[SyncConnectionResolver]
  end
  WSC --> Engine
  WSC --> Store
  Intent --> WSC
  PCS --> Store
  UI --> Store
  WSC --> Sync
  PCS --> Sync
```

| Layer | Own | Avoid |
|-------|-----|--------|
| `WakeTrackerCore` | Models, schema, file store, DetectionEngine, sync *wording* resolvers | UIKit/SwiftUI, WCSession, HealthKit, CoreLocation |
| `WakeTrackerWatch` | `HKWorkoutSession` dry-run, sensors, StartWorkoutIntent, WC send, thin probes into Core | Business decision trees that can be pure functions |
| `wake-tracker` | Permissions, WC receive/ack, session list/map/export | Session engine, label editing |

Apps read live `WCSession` / sensors, then call Core. Do not duplicate detection or sync decision trees in both targets.

## Detection stream

```mermaid
sequenceDiagram
  participant WSC as WatchSessionController
  participant Engine as DetectionEngine
  participant Store as SessionFileStore
  WSC->>Engine: makeSessionStartEvent
  Engine-->>WSC: DetectionEvent session_start paused
  WSC->>Store: appendDetection
  loop GPS updates
    WSC->>Engine: process DetectionTick
    alt code change or lookback
      Engine-->>WSC: DetectionEvent[]
      WSC->>Store: appendDetection
    end
  end
```

- **Detections:** `detections.jsonl` (transitions + `session_start` + lookback revisions; km/h `reason`).
- Codes: `riding` / `paused` / `unsure`.
- Manual labels removed.

Streams detail: [DataCollection.md](DataCollection.md). Thresholds: [Phase3.md](Phase3.md).
