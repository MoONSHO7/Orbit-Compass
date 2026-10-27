# Changelog

## 2026-10-24

* On Forever with Orbit, herbs and ore spotted by the minimap or HUD now appear below the compass as round icons with thin gold borders. They follow Orbit's existing resource setting.

## 2026-10-18

* New Show Arrow option, at the top of the Arrow's Behaviour settings, hides the destination arrow while you play. Waypoints, Auto Advance and Orbit Navigation keep working, and the arrow still shows in Edit Mode so you can turn it back on.
* The destination arrow is sharper, with lighting, a faceted gem and a soft shadow. Its shape and colours are unchanged, and it stays smooth at small sizes.
* With Orbit Navigation (not yet available), the arrow points at the next step of the planned route, even for a waypoint on another continent, and lists every step under the destination like quest objectives, ticking each one off as you finish it.
* With Orbit Navigation and nothing selected in Compass, quests you track from the quest log or world map are routed even when they lie off the current map. Dismissing the route in Compass stops it until the tracked target changes.

## 2026-10-04

* Landmark search stays responsive while you type on large maps. Compass places now appear in Orbit's search once you have typed two letters.

## 2026-09-28

* Standalone Compass bundles the Orbit UI fonts for the ribbon and search. Korean and Chinese clients use the game's own font.
* Fixed confirmation buttons sometimes disappearing from the settings window.

## 2026-09-26

* Names and notes from Kemayo's HandyNotes packs now appear on the compass, and their pins stay in place while a pack is still loading.
* CurseForge now lists Forever 1.60.1 as supported.

## 2026-09-21

* Compass now runs on Forever, on its own or with Orbit.
* Removed the Enabled options from Compass and Arrow settings. Turn Compass on or off from the game's AddOns list; an old disabled setting no longer hides it.

## 2026-09-20

* New landmark search: click the magnifier at the compass's bottom-left and type to find dungeons, raids, delves, zones, cities, flight masters, portals, quest hubs, pet tamers, world quests, rares, treasures, your quests, your saved locations and more. Partial words, any word order and small typos still match, closest first.
* With Orbit, Compass places appear in Orbit's search (in the chat box when Orbit Chat is on), and the ribbon hides its own search field while Orbit's search includes Locations. Standalone Compass keeps its own field.
* The arrow follows the game's own route to map pins, world-map points, search picks and tracked content, pointing at the next portal or zone exit with its travel instruction. Newly placed map pins are tracked automatically.
* Nearby icons are larger: 140% within 150 yards, shrinking smoothly to 45% at 1,000 yards and beyond.
* Restored the original gold glow around the selected point.

## 2026-09-13

* New Auto Advance option in Arrow settings: after you arrive or a point disappears, the arrow moves on to the nearest enabled point, optionally of the same type, skipping places you have already visited.
* GatherMate2 support: one Points option shows every category GatherMate2 has enabled, below the compass line, with arrival-based Auto Advance. Recorded locations do not mean a node has spawned.
* Arrow navigation options now live in a Behaviour tab, with tooltips.
* Points rows for GatherMate2 and HandyNotes only appear when those addons are installed.
* Overlap and nearby selection menus show each point's icon.
* Tracked waypoints stay visible when you toggle Points, and hidden point types no longer trigger Auto Advance.
* The selected point's gold glow is larger.

## 2026-09-12

* Points is now a table with separate Cities and World choices for every point type, and visibility updates as you move between them. A Toggle column and hotkey switch between your two sets of choices.
* Overlapping points stay in their real positions with nearer icons in front. Clicking a group opens a menu to choose which one to track.
* Hold Alt to show the name and distance of the nearest untracked point.
* HandyNotes support: enabled plugin markers appear on the compass, with personal-note text under the arrow's destination name.
* Selecting a point from Zarillion's HandyNotes expansion packs runs its own click action, shows its coloured guide dots on the compass, and adds its tooltip text and numbered instructions under the arrow.
* MapNotes nodes and NPCs show their proper names when selected or tracked, and HandyNotes markers use the normal compass icon size.
* Selecting any point starts arrow navigation, even where Waypoints are hidden.
* Daily and weekly quest offers now appear on the compass.
* The tracking badge is larger and draws above every other icon.
* Removed TomTom integration and the Follow TomTom setting. `/way`, `/orbitway` and `/oway` still work; `/tway` and `/tomtomway` are left to TomTom.
* Fixed an error when compass markers were created during combat.
