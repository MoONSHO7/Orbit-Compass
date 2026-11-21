# Compass discovery

## Description
Validated point data, category visibility and budgeted source caches.

## Purpose
Turn native and addon observations into stable marker snapshots without rescanning on every redraw.

## Implementation
`Discovery.xml` loads validation and visibility before `Sources/`, then snapshot assembly, the collector catalog,
display polling and the scheduler. `CompassSourceUtils.lua` owns secret-first record validation and marker construction.
`CompassPointVisibility.lua` caches Cities, World and Toggle preferences for the 19 point definitions; a point may
name several sources (Available Quests, Quest Objectives and Zone POIs also feed the QuestieDB source). It also owns
scan ranges: `PointRanges` holds optional per-row yards over the global `Range`, and `CompassDiscovery.lua` stamps each
completed marker's `point` from its source and kind, which Navigation and Ribbon resolve through
`GetCompassMarkerRange`. Rows sharing a source must list their `kinds`; markers outside any row use `Range`.
`CompassCities.lua` groups points by place: `RebuildCompassMarkers` ends by stamping each marker with the Foundation
catalogue place that holds it once projected onto the current map: a city's whole map, or a town's terrain outline
within its rectangle. Bounds are read once per map until a context reset, membership once per marker position. The
player is inside a city found in their map ancestry (`RefreshCompassPointArea`), a town the client names as the subzone,
or a town whose outline holds their position (checked on each full bearings refresh, left only `TOWN_EXIT_YARDS` past
the edge). Each bearings ordering moves a place's fold state toward that side over `CITY_FOLD_SECONDS`;
`BlendCompassCityFolds` then fades the icon and glides the selected points out of it, or back in, and the earliest
pending settle reorders the ribbon (`SettleCompassPlaceFolds`) even with every point off screen. The Cities & Towns
Points row (`ShowPlaces`, `showPlaces`) gates folding and the icons; while off, no place bearings, fold states or
position-town checks run, but stamping stays so re-enabling folds at once. Stamping also flags a place that holds any
collected Available Quests point (`offersQuests`), whatever its distance. `GetCompassTownMaps` lists, per map, the
towns on other maps within `RANGE_MAX` of its edge, for collectors that can read those maps. Each icon carries that
row's range and a destination on its own map (a town across a zone border projects outside the current one).
`GetCompassPlaceMarkers` hands Navigation the map's icons to rank as points in their own right; its bearings swap a
folded place's points for its one marker, and its menu lists them. Profiler: `Compass.Cities` spans stamping; `Cities/Bounds`, `Cities/Stamped`,
`Cities/FoldStarted`.
`CompassDiscoveryCatalog.lua` owns collector order and event routing, including the quest-log events the QuestieDB
log owner coalesces itself (`../Integrations/QuestieDB/README.md`). `CompassDiscovery.lua` owns job scheduling,
invalidation and refresh deadlines. `CompassSources.lua` assembles snapshots with the user waypoint and, when absent, the
followed map pin or vignette as a waypoint-priority marker, so a tracked destination shows at any range, even when its
category is hidden or it sits on another map of the same continent.

Native collectors live in `Sources/`; optional-addon collectors stay with their provider under `../Integrations/`,
and their `SOURCES` rows name the `provider` addon that must be loaded. The `navigation` row has no Points field: it
refreshes only when Orbit Navigation's callback invalidates it, and Navigation's settings decide whether it is empty.
Navigation consumes the assembled records for guidance, and Ribbon selects and projects them for display.
`CompassDisplayMarkers.lua` owns the hosted Forever resource adapter's polling state and publishes outside the job
queue. It checks the 0.2-second wall-clock deadline before bearings on visible frames, so hiding or a suspended collector
cannot keep stale observations. Changes publish
`displayMarkers`, a fresh array stamped `displayOnly`; `markers` stays actionable, so Navigation, Search, auto-advance
and waypoint artwork never see observations, while Ribbon merges both lists. Context resets give each row a fresh state
table for its caches. A failing provider clears its published markers, re-raises its error and retries after 30 seconds.

With the optional Orbit profiler active, source timing rows count coroutine resumes. Fixed counters distinguish started,
completed, changed, unchanged, failed and cancelled jobs, including targeted quest paths and invalidation reasons;
`Discovery/PathUnchanged/<key>` counts path wakes settled without a job.
Display polls are timed under their row's label; `Discovery/DisplayChanged/<key>` counts publications.

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
- Same-map subzone events also retain a ready QuestieDB source, which depends only on the map and character.
- Ordinary `ZONE_CHANGED` also retains clean, completed HandyNotes snapshots when readable map artwork matches and no
  retry or active scan remains. Provider notifications still invalidate their own pack. Indoor/new-area events,
  changed/unknown artwork, pending work and map/world/phase transitions refresh normally; area visibility is always
  reconciled.
- Cancelled jobs cannot publish stale results; a failing collector re-raises only after the pass rebuilds from sources
  that completed with it. Change detection also compares route state (`arrival`, `arrived`, `routeTracking`,
  `routeDestination`) and guide flags, which can flip alone. Changed preferences invalidate only affected sources, and
  visibility switches retain completed HandyNotes provider data. A quests pass triggered only by quest-data loads keeps
  the full-scan deadline, like targeted path refreshes. Path events mark only route and quests path-dirty; tracked
  content depends on content/tracking events and its recovery deadline, not navigation-path notifications.
- A path-dirty route settles without a job while its last completed collection's receipt (tracking type, next hop,
  item-sourced name) still matches, including no hop on this map and no route target; unreadable reads and the
  30-second deadline re-collect.
  Every other route input (waypoint, pin choice, landmark index, Follow Targets, map) raises its own invalidation, so a
  new route input needs one too or the receipt will hide its changes.
- City grouping ignores `C_Map.IsCityMap`: Retail flags only Valdrakken, Dornogal and Silvermoon and Forever flags
  none, so each family's catalogue lists maps. Area flags mark no towns either, so towns are generated (see
  Foundation). A town is the terrain the game names it, so it opens where the zone text does: ~70 yards past
  Gadgetzan's south wall, where its overlay hit box reached ~190. A city's whole map rectangle can still fold points
  just outside its walls. Inns and halls are separate subzones; their town's outline covers them.
  The destination, waypoint-priority markers and route steps never fold.
- A place animates only while consecutive orderings include it; first sight or a gap (another continent) snaps, so
  arriving by hearth or portal never replays a fold. Inside a capital or hub, towns share nothing: neither their icon
  nor their folded points reach the ribbon. City detection keys on `cityRegion`, never kind: Search's `IsCityMap`
  results keep kind "city" on an ordinary waypoint.
- Capitals switch maps, and a map change resets the discovery context (sources, bounds, fold state), so a capital
  snaps while towns, being subzones of one map, animate. Kept fold state would animate only points re-collected in time.
- Faction is catalogue data: capitals by hand, towns from their flight masters' TaxiNodes flags, else the zone's
  AreaTable mask (subzones carry none), with two generator overrides. `UnitFactionGroup` is read when a tooltip or menu
  opens; an enemy place still folds, but offers only its points.
- The Points Cities column still follows `IsCityMap` ancestry, which includes child maps; unknown ancestry hides normal
  points until retry. Unconfigured city/world cells
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
