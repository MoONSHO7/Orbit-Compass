# Compass discovery

## Description
Validated point data, category visibility and budgeted source caches.

## Purpose
Turn native and addon observations into stable marker snapshots without rescanning on every redraw.

## Implementation
`Discovery.xml` loads `CompassSourceUtils.lua` and the visibility model before `Sources/`, then the aggregate source and scheduler modules. `CompassSourceUtils.lua` owns secret-first record validation and marker construction. `CompassPointVisibility.lua` caches Cities, World and Toggle preferences. `CompassSources.lua` projects destinations and assembles source snapshots, while `CompassDiscovery.lua` owns the work queue, invalidation and refresh deadlines. Assembly adds the user waypoint and, when no source already provides it, the followed map pin or vignette as a waypoint-priority marker. A tracked destination therefore shows at any range, even when its category is hidden or it sits on another map of the same continent.

Native collectors live in `Sources/`; optional-addon collectors stay with their provider under `../Integrations/`. Navigation consumes the assembled records for guidance, and Ribbon selects and projects them for display.

With the optional Orbit profiler active, source timing rows count coroutine resumes. Fixed counters distinguish started,
completed, changed, unchanged, failed and cancelled jobs, including targeted quest paths and invalidation reasons.

## Gotchas
- Runtime caches reset on world/map/player-phase changes. Source states distinguish unsupported, disabled, pending, ready and failed. Ready-empty confirms absence; incomplete lists merge new valid markers with the prior snapshot and retry after 30 seconds. They cannot confirm removal. Preference changes clear the affected snapshot before recollection.
- Static policy excludes unsupported jobs and their exclusive events. Shared events remain registered while a category is hidden; effective preferences stop its collector work. Missing optional addons are pending providers, not empty datasets.
- Same-map subzone events retain only clean, completed taxi data with matching readable map artwork. Pending taxi work,
  artwork changes, native taxi-status events and preference changes still refresh; the 60-second recovery deadline remains.
- Ordinary `ZONE_CHANGED` also retains clean, completed HandyNotes snapshots when readable map artwork matches and no retry or active scan remains. Provider notifications still invalidate their own pack. Indoor/new-area events, changed/unknown artwork, pending work and map/world/phase transitions refresh normally; area visibility is always reconciled.
- Cancelled jobs cannot publish stale results. Changed preferences invalidate only affected sources, and visibility switches retain completed HandyNotes provider data.
- City ancestry includes child maps; unknown ancestry hides normal points until retry. Unconfigured city/world cells inherit legacy preferences, while Toggle defaults off. Edits copy all three values through the controller.
- The hotkey uses the cached alternate set independently of area; a second press restores the current area. Disable, profile switch and Points reset clear that temporary mode. Effective visibility intersects saved choices with client policy. Points reset clears supported rows only, preserving hidden Retail choices on Forever.
- Explicit POI selections and supertracked user waypoints bypass the Waypoints filter. Selected POIs retain artwork and row identity while their source is filtered out. Visibility changes suspend auto-advance removal detection until the source point is observed again; arrival behavior remains independent. Destination validation clears stale selection identity before filtering.

## Secrets
Native records and coordinates cross secret-first validity gates before arithmetic, indexing or comparisons. Other modules consume only these validated observations.

## References
`../README.md`, `Sources/README.md`, `../Navigation/README.md`, `../Integrations/README.md`; the `wow-secrets` and `orbit-settings` skills.
Blizzard `FlightPointDataProvider.lua`, `Blizzard_MapCanvas.lua` and generated `TaxiMapDocumentation.lua` / `MapDocumentation.lua`.
