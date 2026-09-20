# Orbit host integration

## Description
Optional plugin registration and advanced rendering/Canvas capabilities from a compatible Orbit host.

## Purpose
Preserve Orbit profile ownership and customization while standalone Compass retains its own controller and store.

## Implementation
`../../CompassCompatibility.lua` selects the host before localization. `../../Plugin/Plugin.xml` loads `Orbit.lua` between standalone services and controller construction, allowing the bridge to supply the real Compass plugin. The later `../Integrations.xml` loads `OrbitCanvas.lua` after navigation and controller declarations. Product navigation and formatting remain outside this module.

Search places reach Orbit through LibOrbitSearch rather than this bridge; see `../README.md`.

## Gotchas
- An absent host uses standalone services. An unsupported host or an existing bundled Compass pauses startup, preserving the old controller, commands and bindings. Compatible Retail and Forever hosts use the same bridge; Compass's client policy still gates individual Forever sources.
- A hosted Compass is always active when the addon is installed and enabled. Orbit profile disable flags are ignored, and the shared app shell does not register a redundant Blizzard AddOns category or Enabled checkbox.
- Preserve `Orbit_Compass`, both settings indices and the historical Orbit migration. Do not flatten Orbit profile/Canvas state into the standalone store.
- Hosted settings share tab state between ribbon and arrow; validate the selected tab against the active surface when switching.
- The bridge registers the shared Points renderer on the host layout. Points reset clears supported rows' area/alternate choices and legacy preferences; unsupported client rows retain their values.
- The bridge must load before any feature caches service hooks or the controller. Canvas needs that controller, so it belongs to the later integration phase.

## References
`../README.md`, `../../Plugin/README.md`, `../../Config/README.md`; Orbit `Core/Plugin/README.md` and `Core/Plugin/ExternalUIHost.lua`.
