# Architecture

## Phase 1

```text
Flutter Android App
        |
        | Agent REST + WebSocket
        v
Windows Agent ---- SQLite / workflow packs / media cache
        |
        | ComfyUI REST + WebSocket
        v
ComfyUI at a configurable loopback address
```

The Agent is the source of truth for workflows, tasks, and output media. The
mobile database is a reconnectable local projection.

## Boundaries

1. The mobile app sends `workflowId`, `workflowRevision`, and user-facing input
   values. It does not send an arbitrary ComfyUI prompt graph.
2. The Agent validates values, deep-copies the API-format workflow, and applies
   allow-listed declarative mappings.
3. Private fields such as node IDs, class types, file paths, and mapping rules
   are removed from the workflow catalogue returned to the app.
4. ComfyUI WebSocket events are converted into stable domain events before they
   reach the app.
5. HTTP task snapshots remain authoritative. WebSocket delivery is an
   optimization for real-time UX and can be safely reconnected.

## Task states

```text
pending -> uploading -> queued -> running -> processing -> completed
                                      |             |
                                      +-----------> failed
                                      +-----------> cancelled
```

The mock provider skips ComfyUI but uses the same task and event contracts.

