# Compass integrations

## Description
Optional Orbit, HandyNotes, GatherMate2, Orbit Navigation and LibOrbitSearch adapters for the Compass controller.

## Purpose
Keep external addon contracts and lifecycle hooks with their provider while using the same navigation and discovery
owners.

## Implementation
`Integrations.xml` loads the [HandyNotes module](HandyNotes/README.md), optional-addon lifecycle methods, the
GatherMate2 adapter, the LibOrbitSearch provider, the Orbit Navigation adapter and the late
[Orbit Canvas adapter](Orbit/README.md). `CompassIntegrations.lua` connects enabled providers and observes late addon
loads.

`CompassSearchProvider.lua` registers Compass as the `locations` provider of the shared LibOrbitSearch library whenever
Compass is enabled, with or without Orbit. Each search session owns scratch, acquires catalog demand and invalidates on
catalog revisions; records wrap frozen landmarks with a stable `id` and the search tier. Activation reuses
`ChooseCompassSearchResult`, returns replacement text for continents, and reports refusal reasons as messages.
`IsCompassSearchHosted` is true while an enabled search in another addon lists and enables places (Orbit's Spotlight),
which hides the ribbon's own magnifier and field; `InclusionChanged` marks the ribbon dirty. The inclusion callback
caches that answer so ribbon rendering never enumerates searches or settings, and provider startup, cleanup and
activation are timed at LibOrbitSearch's protected call boundary.

`CompassGatherMate.lua` snapshots GatherMate2's current-map iterators for every registered category, localized names and
node artwork. Discovery consumes validated records under one GatherMate2 Points filter, on by default. Icons use 60% of
the normal marker size. AceEvent database/configuration messages invalidate its source; a 30-second refresh also
reconciles imports and enablement changes. Disable unregisters the owned message receiver.

`CompassNavigationRoute.lua` talks to Orbit Navigation only through its frozen `_G.OrbitNavigation` table
(`API_VERSION == 1`, validated like GatherMate2); Navigation never references Compass. Both directions:
- **Destination out.** `../Navigation/CompassTargets.lua` calls `PublishCompassNavigationDestination` after ranking:
  the nearest `selected` marker's destination; else `false` after the user dismissed the route or the selected native
  target; else the adopted user waypoint when no native selection applies (the marker is absent when the waypoint lies
  on another continent); else `ReleaseDestination`, so Navigation follows the native super-track (an off-map quest or
  pin). The record is stored first and either call runs only on change; disconnect also releases.
- **Guidance in.** Navigation's change callback invalidates the `navigation` discovery source
  (`ORBIT_COMPASS_NAVIGATION_ROUTE`); its collector turns `GetGuidance(mapID)` into one kind-`route` marker whose
  position is the current step's endpoint and destination is the goal. Navigation's `steps` appear with finished steps
  ticked and greyed, the current `step` white, the rest dimmed, at most six lines (two finished), with the objective tracker's
  check and nub atlases; without steps it is the localized leg text. `../Navigation/CompassTargets.lua` ranks it above
  the native route step. `GetWaypointLabel` names waypoints that Navigation's nearest buttons placed.

The Orbit registration bridge has an earlier phase: `../Plugin/Plugin.xml` loads `Orbit/Orbit.lua` before the controller
and before consumers capture service hooks. Its `OrbitCanvas.lua` companion loads here after Navigation declarations.

## Gotchas
- Optional integrations must remain inert while Compass is disabled, including hooks that cannot be uninstalled.
  Lifecycle owns activation and retirement.
- LibOrbitSearch loads after LibStub. Packaging pins its verified 1.4 release through the `Libs/LibOrbitSearch-1.0`
  external in `.pkgmeta`; release-mode `.scripts/check-package.py` verifies the loaded provider APIs. Local links cannot
  satisfy delivery. Provider functions read Compass through controller methods; landmarks stay frozen. Missing native
  atlases present the bundled arrow to the shared Search host.
- Orbit and standalone stores have separate ownership. Provider adapters feed observations and explicit selection
  actions; they must not bypass the selected controller's settings or navigation path.
- Complete HandyNotes snapshots remain cached until provider/context changes. Native waypoint ownership survives
  disabling Compass; stale integration markers are released through discovery invalidation.
- Orbit Navigation must not list Orbit_Compass as a dependency (only Compass declares the optional edge). `false` is
  reserved for dismissals and must stay distinct from release, or Navigation would revive the dismissed trip from the
  native super-track; publishing `false` for "nothing selected" blocked natively tracked quests. Provider calls are
  protected; each distinct failure is logged once.
  Guidance changes rebuild markers at most every `DISCOVERY_MIN_INTERVAL`; a hidden ribbon publishes nothing new.
- GatherMate2 records are known spawn locations, not live minimap detections. Harvesting preserves those records; use
  arrival-based auto-advance. GatherMate's resolved category visibility and per-node filters apply in addition to
  Compass's Cities/World/Toggle choices. External iterators finish before discovery yields so database mutation cannot
  invalidate a suspended cursor. The adapter never writes provider data or settings.

## Secrets
`CompassGatherMate.lua` reads the GatherMate2 object, its iterators, coordinates and texture tables through
`SourceUtils.Readable`/`Number` before indexing or arithmetic; `CompassNavigationRoute.lua` validates Navigation's API
table, guidance, coordinates and labels the same way; `CompassSearchProvider.lua` hands the search host frozen
landmarks only. HandyNotes validation is described in its own README.

## References
`../README.md`, `Orbit/README.md`, `HandyNotes/README.md`, `../Discovery/README.md`, `../Navigation/README.md`,
`../Search/README.md`; `Orbit/Orbit/Core/Navigation/README.md` owns the built-in `_G.OrbitNavigation` contract.
GatherMate2 `GatherMate2.lua` (`GetNodesForZone`, `DecodeLoc`, AceEvent messages) and `Constants.lua`
(`nodeTextures`), verified against upstream master on 2026-09-13.
