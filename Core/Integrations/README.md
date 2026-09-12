# Compass integrations

## Description
Optional Orbit and HandyNotes adapters for the Compass controller.

## Purpose
Keep external addon contracts and lifecycle hooks with their provider while using the same navigation and discovery owners.

## Implementation
`Integrations.xml` loads the [HandyNotes module](HandyNotes/README.md), optional-addon lifecycle methods and the late [Orbit Canvas adapter](Orbit/README.md). `CompassIntegrations.lua` connects enabled providers and observes late addon loads.

The Orbit registration bridge has an earlier phase: `../Plugin/Plugin.xml` loads `Orbit/Orbit.lua` before the controller and before consumers capture service hooks. Its `OrbitCanvas.lua` companion loads here after Navigation declarations.

## Gotchas
- Optional integrations must remain inert while Compass is disabled, including hooks that cannot be uninstalled. Lifecycle owns activation and retirement.
- Orbit and standalone stores have separate ownership. Provider adapters feed observations and explicit selection actions; they must not bypass the selected controller's settings or navigation path.
- Complete HandyNotes snapshots remain cached until provider/context changes. Native waypoint ownership survives disabling Compass; stale integration markers are released through discovery invalidation.

## References
`../README.md`, `Orbit/README.md`, `HandyNotes/README.md`, `../Discovery/README.md`, `../Navigation/README.md`.
