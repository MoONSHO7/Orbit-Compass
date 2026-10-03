# Orbit Compass

## Description
An independently installed navigation ribbon and destination arrow built on LibOrbitUI, with an optional Orbit host
bridge.

## Purpose
Keep native map points, saved locations, HandyNotes and GatherMate2 markers, world-wide landmark search and waypoint
commands usable without Orbit. A compatible Orbit supplies its profile, theme, fade, layering and Canvas services in
place of the standalone store.

## Implementation
- **Load order.** `Orbit_Compass.toc` loads the embedded libraries (`Libs/LibOrbitUI-1.0`, `Libs/LibStub`,
  `Libs/LibOrbitSearch-1.0`), `Core/Foundation/CompassClientFeatures.lua` (frozen client policy),
  `Core/CompassCompatibility.lua` (host selection), `Localization/Localization.xml` and `Core/Core.xml`. Core follows
  Orbit's module conventions: Foundation, Plugin, Discovery, Navigation, Integrations, Ribbon, Search and Config each
  own a directory, XML bundle and README; [Core/README.md](Core/README.md) maps the data flow and startup phases.
  `Assets/` owns the arrow texture, logo and private fonts.
- **Orbit boundary.** The TOC declares `## OptionalDeps: Orbit, HandyNotes, GatherMate2`.
  `Core/CompassCompatibility.lua` accepts a host only when `Orbit.ExternalUIHost.legacyPluginVersion == 1` and no
  `Compass` plugin is already registered; it exports `Addon.OrbitHost` or sets `Addon.incompatibleOrbit`.
  `Core/Integrations/Orbit/Orbit.lua` is the bridge: it registers the real `Orbit_Compass` plugin (indices 1 and 2 plus
  the `CompassLocations` collection) and rebinds the `Services` hooks (pixel, tooltip, profiler, fonts, text styling,
  strata, persistence, Edit Mode, secret labelling); `OrbitCanvas.lua` adds Canvas text editing for the arrow.
  `Core/CompassBoot.lua` always creates the LibOrbitUI `UI.Addon` shell and its `move`/`reset` commands; without a
  bridge it also owns `OrbitCompassDB`, the settings window, Edit Mode entry, native font, gold arrow text, standard
  text placement and configurable units, name and distance text. Both modes run the same Discovery, Navigation, Ribbon,
  Search, HandyNotes, GatherMate2 and command code. Search places reach Orbit's Spotlight through LibOrbitSearch, not
  through the bridge.
- **Player surface.** `/orbitcompass` opens Appearance and Points settings; `/orbitcompass move` enters Edit Mode and
  `reset` restores the ribbon. Points selects visibility in Cities, World and an alternate Toggle column, including
  HandyNotes and GatherMate2, and a hotkey above the table switches between the current area and the Toggle choices.
  Zarillion's packs provide native tooltips, numbered instructions and coloured guide dots; following a dot keeps the
  note's instructions. Hold Alt to label the nearest visible untracked POI. The search field at the ribbon's bottom-left
  finds any dungeon, raid, delve, zone, city, continent, flight master, portal or named point; category words ("raids",
  "flight masters") and place names ("Khaz Algar") narrow the list. With a compatible Orbit the ribbon hides its own
  search because places appear in Orbit's search instead. Tracked world-map pins, placed map pins and search choices
  follow the game's own route, including portal shortcuts. Arrow controls live in Compass: Arrow settings, opened by
  selecting the arrow in Edit Mode. `/oway` and `/orbitway` keep waypoint, saved-location and nearby-target commands;
  `/way` is claimed only when free. `ORBIT_COMPASS_TARGET` and `ORBIT_COMPASS_TOGGLE_POINTS` are this addon's bindings.
- **GatherMate2.** One GatherMate2 row in Points shows recorded locations for every category enabled in GatherMate2;
  import GatherMate2_Data there for a prebuilt database. Records are possible spawn locations, and arrival-based
  auto-advance can visit them in sequence.
- **Packaging.** `.pkgmeta` defines the `Orbit_Compass` package and pins embedded libraries to full commits. The TOC
  declares CurseForge project `1689597`; the packager replaces `@project-version@`. `.github/workflows/release.yml`
  validates the package, runs `.scripts/check-client-features.py`, and creates a stable `MAJOR.MINOR` tag from `main` or
  publishes an existing version tag. Build directories and source documentation stay outside the runtime ZIP.

## Gotchas
- Standalone settings (`OrbitCompassDB`) and Orbit profiles are separate stores. Installing the addon never copies or
  overwrites either.
- Compass and its arrow stay active whenever the addon is enabled in WoW; neither exposes an Enabled control and legacy
  false values are ignored. When hosted, Orbit owns runtime lifecycle, profiles, themes, fade, layer order, frame
  anchoring and Canvas text customization.
- An incompatible Orbit, or an Orbit that still carries a bundled Compass, pauses this addon with an update/disable
  warning and preserves the existing Compass, commands and settings; disabling Orbit allows standalone startup after
  reload.
- Both surfaces stop navigation discovery inside instances. Native pins survive disable.
- Forever runs standalone or through a compatible Orbit host with ordinary quests, map points, entrances and navigation.
  World Quests/tasks, Delves, races, tamers, archaeology, tracked content and Housing pins remain withheld. Retail keeps
  its choices; unknown clients stay dormant.
- Saved destinations carry client family and optional world-instance identity. Old unclassified records stay stored but
  cannot navigate; re-save confirmed places on their originating client. See `Core/Navigation/README.md`.
- Pins are the verified LibOrbitUI 1.7 (API 1.9) and LibOrbitSearch 1.1 (revision 3) releases. Validate ordinary fetched
  files before consumer publication; local junctions are development-only, and automatic latest-published-release
  resolution is not implemented. Orbit-Libs is public; packaging keeps its Git credential policy plus a CurseForge
  upload token.

## References
`Core/README.md`, `Localization/README.md`, `Assets/README.md`, `.scripts/README.md`, `.github/workflows/README.md`,
`.pkgmeta`, and the workspace Orbit addon standards.
