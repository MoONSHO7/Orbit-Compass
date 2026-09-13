# Compass integrations

## Description
Optional Orbit, HandyNotes and GatherMate2 adapters for the Compass controller.

## Purpose
Keep external addon contracts and lifecycle hooks with their provider while using the same navigation and discovery owners.

## Implementation
`Integrations.xml` loads the [HandyNotes module](HandyNotes/README.md), optional-addon lifecycle methods and the late [Orbit Canvas adapter](Orbit/README.md). `CompassIntegrations.lua` connects enabled providers and observes late addon loads.

`CompassGatherMate.lua` snapshots GatherMate2's current-map iterators for every registered category, localized names and node artwork. Discovery consumes validated records under one GatherMate2 Points filter, on by default. Icons use 60% of the normal marker size. AceEvent database/configuration messages invalidate its source; a 30-second refresh also reconciles imports and enablement changes. Disable unregisters the owned message receiver.

The Orbit registration bridge has an earlier phase: `../Plugin/Plugin.xml` loads `Orbit/Orbit.lua` before the controller and before consumers capture service hooks. Its `OrbitCanvas.lua` companion loads here after Navigation declarations.

## Gotchas
- Optional integrations must remain inert while Compass is disabled, including hooks that cannot be uninstalled. Lifecycle owns activation and retirement.
- Orbit and standalone stores have separate ownership. Provider adapters feed observations and explicit selection actions; they must not bypass the selected controller's settings or navigation path.
- Complete HandyNotes snapshots remain cached until provider/context changes. Native waypoint ownership survives disabling Compass; stale integration markers are released through discovery invalidation.
- GatherMate2 records are known spawn locations, not live minimap detections. Harvesting preserves those records; use arrival-based auto-advance. GatherMate's resolved category visibility and per-node filters apply in addition to Compass's Cities/World/Toggle choices. External iterators finish before discovery yields so database mutation cannot invalidate a suspended cursor. The adapter never writes provider data or settings.

## References
`../README.md`, `Orbit/README.md`, `HandyNotes/README.md`, `../Discovery/README.md`, `../Navigation/README.md`.
GatherMate2 `GatherMate2.lua` (`GetNodesForZone`, `DecodeLoc`, AceEvent messages) and `Constants.lua` (`nodeTextures`), verified against upstream master on 2026-09-13.
