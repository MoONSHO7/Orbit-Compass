# Compass discovery

## Description
Validated point data, category visibility and budgeted source caches.

## Purpose
Turn native and addon observations into stable marker snapshots without rescanning on every redraw.

## Implementation
`Discovery.xml` loads `CompassSourceUtils.lua` and the visibility model before `Sources/`, then the aggregate source and scheduler modules. `CompassSourceUtils.lua` owns secret-first record validation and marker construction. `CompassPointVisibility.lua` caches Cities, World and Toggle preferences. `CompassSources.lua` projects destinations and assembles source snapshots, while `CompassDiscovery.lua` owns the work queue, invalidation and refresh deadlines.

Native collectors live in `Sources/`; optional-addon collectors stay with their provider under `../Integrations/`. Navigation consumes the assembled records for guidance, and Ribbon selects and projects them for display.

With the optional Orbit profiler active, source timing rows count coroutine resumes. Fixed counters distinguish started,
completed, changed, unchanged, failed and cancelled jobs, including targeted quest paths and invalidation reasons.

## Gotchas
- Runtime caches reset on world/map/player-phase changes. Same-map scans replace a source snapshot only when complete; an empty result is valid, while incomplete observations retain a retry.
- Same-map subzone events retain only clean, completed taxi data with matching readable map artwork. Pending taxi work,
  artwork changes, native taxi-status events and preference changes still refresh; the 60-second recovery deadline remains.
- Cancelled jobs cannot publish stale results. Changed preferences invalidate only affected sources, and visibility switches retain completed HandyNotes provider data.
- City ancestry includes child maps; unknown ancestry hides normal points until retry. Unconfigured city/world cells inherit legacy preferences, while Toggle defaults off. Edits copy all three values through the controller.
- The hotkey uses the cached alternate set independently of area; a second press restores the current area. Disable, profile switch and Points reset clear that temporary mode.
- Explicit POI selections keep their navigation target when the Waypoints category is hidden. Destination validation clears stale selection identity before that filter; corpse guidance remains independent.

## Secrets
Native records and coordinates cross secret-first validity gates before arithmetic, indexing or comparisons. Other modules consume only these validated observations.

## References
`../README.md`, `Sources/README.md`, `../Navigation/README.md`, `../Integrations/README.md`; the `wow-secrets` and `orbit-settings` skills.
Blizzard `FlightPointDataProvider.lua`, `Blizzard_MapCanvas.lua` and generated `TaxiMapDocumentation.lua` / `MapDocumentation.lua`.
