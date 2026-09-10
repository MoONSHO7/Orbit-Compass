# Compass Orbit integration

## Description
Optional registration and rendering capabilities supplied by an installed compatible Orbit host.

## Purpose
Retain existing Orbit profile/settings ownership and advanced Canvas customization while the product runs independently.

## Implementation
`../CompassCompatibility.lua` selects the host before localization and controller construction. `Orbit.lua` binds explicit services to that host and creates its real `Compass` plugin. `OrbitCanvas.lua` adds arrow preview and transaction behavior only when that bridge is selected. Product navigation and formatting remain outside this module.

## Gotchas
- An absent host uses standalone services. An unsupported host or existing bundled Compass pauses startup with a warning, preserving the old controller, commands and bindings.
- Preserve `Orbit_Compass`, both settings indices and the historical Orbit migration; do not flatten profile or Canvas state into standalone settings.
- The hosted settings dialog shares tab state between ribbon and arrow; validate its selected tab against the active surface to keep controls visible when switching.

## References
`../README.md`, Orbit `Core/Plugin/README.md` and `Core/Plugin/ExternalUIHost.lua` contracts.
