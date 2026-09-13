# Changelog

## Unreleased

- Keep tracked waypoints visible across Points toggles, preserve their artwork and row, and prevent filtered-out points from triggering auto-advance removal.

- Hide GatherMate2 and HandyNotes Points rows unless the corresponding addon is loaded.

- Group Arrow navigation controls in a Behaviour tab with tooltips for Auto Advance, same-type routing, Corpse Recovery and Follow Selected Map Targets. Auto Advance is now an arrival-or-removal checkbox.

- Place GatherMate2 markers below the compass line, with flipped selection artwork and overlap selection separate from the upper row.

- Integrate all enabled GatherMate2 categories through one Points option, following its category and node filters. Show localized names and provider icons at 60% size, with arrival-based auto-advance. The option starts enabled; recorded locations do not indicate live spawns.

- Add optional auto-advance in Arrow settings: choose the nearest enabled point after source removal or arrival, optionally keep the same point type, and skip visited points within the current selection sequence.

- Show each point's icon on the right of overlap and nearby selection menu entries.

- Remove TomTom selection integration and its Follow TomTom setting. Retain /way, /orbitway and /oway; stop claiming /tway and /tomtomway.

- Reduce repeated marker geometry and distance sorting, skip unusable quest and navigation queries, and retain unchanged taxi data across subzone changes. Add profiler phases and discovery job counters while preserving movement and navigation update timing.
- Organize Core into focused modules with XML load bundles and local READMEs, following Orbit’s directory conventions while preserving Lua behavior and settings.
- Declare marker and arrow click-through behavior in XML templates to avoid protected `SetPassThroughButtons` calls when buttons are created during combat.
- Add a Toggle column and a Spotlight-styled hotkey selector to Points; press the assigned key to switch between Cities/World preferences and the alternate selections. Rename Open World to World. Explain each view on column-heading hover, with 2px below the header and extra space above it. Switching views reuses completed HandyNotes provider data without polling.
- Double the selected POI's gold glow width and height and move it down 2 physical pixels.
- Hold Alt to reveal only the nearest visible, untracked POI's name and distance in a callout connected to its icon, using existing marker caches.
- Selecting a point from any of Zarillion's 12 HandyNotes expansion packs runs its native click action and shows its coloured guide dots on the compass. Each dot uses its own pack's artwork, is trackable and retains the parent's instructions; guide snapshots use existing provider refreshes without additional polling. Overlap and nearby choices preserve provider and node identity.
- Render arrow note instructions in smaller white PT Sans Narrow text with padding beneath the name, independently of destination-name style customizations. Use HandyNotes' coloured circle textures within steps to avoid missing font glyphs.
- Start arrow navigation when selecting a HandyNotes marker or other POI even if Waypoints are hidden for the current area.
- Show Zarillion HandyNotes packs' native tooltip content on compass hover and carry localized node names and numbered instructions beneath the tracked arrow's name. Cache resolved text and cancel delayed tooltip rendering when the marker is no longer hovered.
- Use MapNotes node names and cached localized NPC names/roles for compass selection and tracking. Normalize HandyNotes markers to the compass icon size instead of inheriting enlarged map scales.
- Detect HandyNotes and cache enabled plugin markers until their data, settings or map context changes, replacing five-second rescans. The Points table controls visibility in Cities and Open World; icons and tracking are preserved, and personal-note descriptions appear beneath the arrow's destination name.
- Include task-derived daily and weekly quest offers and refresh them when quest positions or titles load.
- Enlarge the tracking selection badge by 56.25% and draw it above all POI icons.
- Draw overlapping POIs at their normal positions with closer icons in front of farther ones. Clicking a grouped icon opens a menu to choose which point to track; individual icons still track directly.
- Replace the Points checkbox list with a table of Cities and Open World visibility choices for every point type. Existing preferences initialize both areas, and visibility updates as the player changes areas.
- Require LibOrbitUI API 1.5 for the standalone settings widget registration hook.
