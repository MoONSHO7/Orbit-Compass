# Orbit Compass

## Description
An independently installed navigation ribbon and destination arrow using LibOrbitUI.

## Purpose
Keep native points, saved locations, HandyNotes markers and waypoint commands usable without Orbit. An optional Orbit bridge supplies its existing profile, theme, fade, layering and Canvas integration.

Optional GatherMate2 supplies recorded locations for all its enabled categories through one GatherMate2 row in Points. Choose categories and individual nodes in GatherMate2; import GatherMate2_Data through GatherMate2 for a prebuilt database. These are possible spawn locations, and arrival-based auto-advance can visit them in sequence.

## Implementation
`Orbit_Compass.toc` loads the embedded UI library, host compatibility selection, `Localization/Localization.xml` and `Core/Core.xml`. Core follows Orbit’s module conventions: Foundation, Plugin, Config, Discovery, Navigation, Ribbon and Integrations each own a focused directory, XML load bundle and README. [Core/README.md](Core/README.md) maps the data flow and startup phases. The standalone controller stores settings and saved locations in `OrbitCompassDB`; the real Orbit plugin retains `Orbit_Compass` indices 1 and 2 and its profile collection when the host is available. `Assets/` owns the arrow texture.

`/orbitcompass` opens Appearance and Points settings; Points selects visibility in Cities, World and an alternate Toggle column, including HandyNotes. Assign a hotkey above the table to switch between the current area and the Toggle choices. Zarillion's expansion packs provide native tooltips, instructions and coloured guide dots; following a dot keeps the note's instructions. Each pack uses its own artwork. Hold Alt to label the nearest visible POI that is not already tracked. `move` enters native Edit Mode and `reset` restores the ribbon. Arrow controls live in Compass: Arrow settings, opened by selecting it in Edit Mode. `/oway` and `/orbitway` retain waypoint, saved-location and nearby-target commands; `/way` is claimed only when available. `ORBIT_COMPASS_TARGET` and `ORBIT_COMPASS_TOGGLE_POINTS` belong to this addon.

`.pkgmeta` defines the `Orbit_Compass` runtime package and pins embedded dependencies to full commits. The TOC declares CurseForge project `1689597`; the packager replaces `@project-version@`. The GitHub release pipeline validates the package before creating a stable `MAJOR.MINOR` tag from `main` or publishing an existing version tag. Build/staging directories and source documentation stay outside the runtime ZIP.

## Gotchas
- Standalone settings and Orbit profiles have separate storage. Installing the addon does not silently copy or overwrite either store.
- Standalone starts enabled with native font, gold arrow text, standard text placement and configurable units/name/distance. A compatible Orbit host owns enablement, profiles, themes, fade, layer order, frame anchoring and Canvas text customization.
- An incompatible Orbit version or an already registered bundled Compass pauses this addon with an update/disable warning. It preserves the existing Compass, commands and settings; disabling Orbit allows standalone startup after reload.
- Both surfaces stop navigation discovery inside instances. Native pins survive disable.
- Points requires LibOrbitUI API 1.5 for consumer widget registration, provided by the pinned [monorepo release 1.2](https://github.com/MoONSHO7/Orbit-Libs/releases/tag/LibOrbitUI-1.2). Package validation checks the fetched API and widget hook. Automatic latest-published-release resolution is not implemented.
- Orbit-Libs is public; GitHub packaging retains its existing Git credential policy plus a CurseForge upload token. Validate fetched ordinary files; development junctions do not prove the packaged dependency contents.

## References
`Core/README.md`, `Localization/README.md`, `Assets/README.md`, `.pkgmeta`, and the workspace Orbit addon standards.
