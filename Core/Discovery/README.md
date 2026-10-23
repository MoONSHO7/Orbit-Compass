# Compass discovery

## Description
Validated point data, category visibility and budgeted source caches.

## Purpose
Turn native and addon observations into stable marker snapshots without rescanning on every redraw.

## Implementation
`Discovery.xml` loads `CompassSourceUtils.lua` and the visibility model before `Sources/`, then the aggregate source and
scheduler modules. `CompassSourceUtils.lua` owns secret-first record validation and marker construction.
`CompassPointVisibility.lua` caches Cities, World and Toggle preferences for the 18 point definitions.
`CompassSources.lua` projects destinations and assembles source snapshots, while `CompassDiscovery.lua` owns the work
queue, invalidation and refresh deadlines. Assembly adds the user waypoint and, when no source already provides it, the
followed map pin or vignette as a waypoint-priority marker, so a tracked destination shows at any range, even when its
category is hidden or it sits on another map of the same continent.

Native collectors live in `Sources/`; optional-addon collectors stay with their provider under `../Integrations/`,
and their `SOURCES` rows name the `provider` addon that must be loaded. The `navigation` row has no Points field: it
refreshes only when Orbit Navigation's callback invalidates it, and Navigation's settings decide whether it is empty.
Navigation consumes the assembled records for guidance, and Ribbon selects and projects them for display.
The hosted Forever `resources` source samples the existing map observations at the 0.2-second discovery cadence,
with no native scan demand; its adapter and copied observation boundary live in `../Integrations/Orbit/`.
An optional synchronous reuse check can settle a due empty source without allocating a collection job; it advances
the same deadlines and clears dirty state only after the source confirms reuse. Resource reuse requires no published
markers and a readable zero observation count; positive or unknown counts retain collection and projection. Reuse
checks share collector error propagation and retry backoff, so a failed provider cannot retry every rendered frame.
Optional source validators run after collection and snapshot comparison, synchronously before publication. They must
not yield; resource validation rejects records retired while either earlier stage was suspended.
Published live resources also revalidate before rendering on wall-clock deadlines. Snapshot replacement preserves any
array borrowed by a suspended comparison, and publication detects that replacement even when its own result is unchanged.
Display-only observations cannot supply a coincident waypoint's artwork or type; that destination keeps its own identity.

With the optional Orbit profiler active, source timing rows count coroutine resumes. Fixed counters distinguish started,
completed, changed, unchanged, failed and cancelled jobs, including targeted quest paths and invalidation reasons.
`Discovery/EmptyReused/resources` counts polls settled without creating a job.

## Gotchas
- Runtime caches reset on world/map/player-phase changes. Source states distinguish unsupported, disabled, pending,
  ready and failed. Ready-empty confirms absence; incomplete lists merge new valid markers with the prior snapshot and
  retry after `SOURCE_RETRY_INTERVAL` (30 seconds). They cannot confirm removal. Preference changes clear the affected
  snapshot before recollection.
- Static policy excludes unsupported jobs and their exclusive events. Shared events remain registered while a category
  is hidden; effective preferences stop its collector work. Missing optional addons are pending providers, not empty
  datasets. Source events advance the existing scheduler deadline only for enabled sources; provider availability
  wakes pending providers immediately. Missing map dimensions retain the map-recovery deadline.
- Same-map subzone events retain only clean, completed taxi data with matching readable map artwork. Pending taxi work,
  artwork changes, native taxi-status events and preference changes still refresh; the 60-second recovery deadline
  remains.
- Ordinary `ZONE_CHANGED` also retains clean, completed HandyNotes snapshots when readable map artwork matches and no
  retry or active scan remains. Provider notifications still invalidate their own pack. Indoor/new-area events,
  changed/unknown artwork, pending work and map/world/phase transitions refresh normally; area visibility is always
  reconciled.
- Cancelled jobs cannot publish stale results. Changed preferences invalidate only affected sources, and visibility
  switches retain completed HandyNotes provider data. A quests pass triggered only by quest-data loads keeps the
  full-scan deadline, like targeted path refreshes. Path events invalidate only route and targeted quest data; tracked
  content depends on content/tracking events and its recovery deadline, not navigation-path notifications.
- City ancestry includes child maps; unknown ancestry hides normal points until retry. Unconfigured city/world cells
  inherit legacy preferences, while Toggle defaults off. Edits copy all three values through the controller.
- The hotkey uses the cached alternate set independently of area; a second press restores the current area. Disable,
  profile switch and Points reset clear that temporary mode. Effective visibility intersects saved choices with client
  policy. Points reset clears supported rows only, preserving hidden Retail choices on Forever.
- Explicit POI selections and supertracked user waypoints bypass the Waypoints filter. Selected POIs retain artwork and
  row identity while their source is filtered out. Visibility changes suspend auto-advance removal detection until the
  source point is observed again; arrival behavior remains independent. Destination validation clears stale selection
  identity before filtering.

## Secrets
`CompassSourceUtils.lua` is the boundary: `Readable` and `Number` call `Services.IsSecret` (label `Compass.MapData`)
before any native record or coordinate reaches arithmetic, indexing or comparison. Other modules consume only these
validated observations.

## References
`../README.md`, `Sources/README.md`, `../Navigation/README.md`, `../Integrations/README.md`; the `wow-secrets` and
`orbit-settings` skills. Blizzard `FlightPointDataProvider.lua`, `Blizzard_MapCanvas.lua` and generated
`TaxiMapDocumentation.lua` / `MapDocumentation.lua`.
