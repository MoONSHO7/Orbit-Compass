# Orbit host integration

## Description
Optional plugin registration and advanced rendering/Canvas capabilities from a compatible Orbit host.

## Purpose
Preserve Orbit profile ownership and customization while standalone Compass retains its own controller and store.

## Implementation
`../../CompassCompatibility.lua` selects the host before localization. `../../Plugin/Plugin.xml` loads `Orbit.lua` between standalone services and controller construction, allowing the bridge to supply the real Compass plugin. The later `../Integrations.xml` loads `OrbitCanvas.lua` after navigation and controller declarations. Product navigation and formatting remain outside this module.

## Gotchas
- An absent host uses standalone services. An unsupported host or an existing bundled Compass pauses startup, preserving the old controller, commands and bindings.
- Preserve `Orbit_Compass`, both settings indices and the historical Orbit migration. Do not flatten Orbit profile/Canvas state into the standalone store.
- Hosted settings share tab state between ribbon and arrow; validate the selected tab against the active surface when switching.
- The bridge registers the shared Points renderer on the host layout. Resetting Points clears all area/alternate choices and inherited legacy preferences.
- The bridge must load before any feature caches service hooks or the controller. Canvas needs that controller, so it belongs to the later integration phase.

## References
`../README.md`, `../../Plugin/README.md`, `../../Config/README.md`; Orbit `Core/Plugin/README.md` and `Core/Plugin/ExternalUIHost.lua`.
