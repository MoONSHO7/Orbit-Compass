# Orbit Compass

## Description
An independently installed navigation ribbon and destination arrow using LibOrbitUI.

## Purpose
Keep native points, saved locations, waypoint commands and TomTom selection usable without Orbit. An optional Orbit bridge supplies its existing profile, theme, fade, layering and Canvas integration.

## Implementation
`Orbit_Compass.toc` loads the embedded UI library and host compatibility selection before localization, product defaults, services and the `Core/` navigation modules. The standalone controller stores settings and saved locations in `OrbitCompassDB`; the real Orbit plugin retains `Orbit_Compass` indices 1 and 2 and its profile collection when the host is available. `Assets/` owns the arrow texture.

`/orbitcompass` opens the ribbon's Appearance and Points settings; `move` enters native Edit Mode and `reset` restores the ribbon. Arrow controls live only in the separate Compass: Arrow settings dialog, opened by selecting the arrow in Edit Mode. `/oway` and `/orbitway` retain waypoint, saved-location and nearby-target commands; `/way`, `/tway` and `/tomtomway` are claimed only when available. The existing `ORBIT_COMPASS_TARGET` binding now belongs to this addon.

`.pkgmeta` defines the `Orbit_Compass` runtime package and pins embedded dependencies to full commits. The TOC declares CurseForge project `1689597`; the packager replaces `@project-version@`. The GitHub release pipeline validates the package before creating a stable `MAJOR.MINOR` tag from `main` or publishing an existing version tag. Build/staging directories and source documentation stay outside the runtime ZIP.

## Gotchas
- Standalone settings and Orbit profiles have separate storage. Installing the addon does not silently copy or overwrite either store.
- Standalone starts enabled with native font, gold arrow text, standard text placement and configurable units/name/distance. A compatible Orbit host owns enablement, profiles, themes, fade, layer order, frame anchoring and Canvas text customization.
- An incompatible Orbit version or an already registered bundled Compass pauses this addon with an update/disable warning. It preserves the existing Compass, commands and settings; disabling Orbit allows standalone startup after reload.
- Both surfaces stop navigation discovery inside instances. Native pins and TomTom ownership survive disable.
- `.pkgmeta` pins a pushed LibOrbitUI source commit providing API 1.4. No versioned GitHub library release exists yet; the immutable source pin and runtime validator supply the packaging contract.
- GitHub packaging needs read access to the LibOrbitUI repository plus a CurseForge upload token. Validate fetched ordinary files; development junctions do not prove the packaged dependency contents.

## References
`Core/README.md`, `Localization/README.md`, `Assets/README.md`, `.pkgmeta`, and the workspace Orbit addon standards.
