# Changelog

## 2026-11-21

* Hover a point type in Points to see what it shows. On Forever, Available Quests now appears only with QuestieDB installed, since the game lists no quest givers itself.
* Icons on the compass now shrink gradually across your whole Marker Range, or a point type's own range, instead of reaching their smallest size at 1,000 yards, so you can still tell near from far at long ranges.
* Outside a capital, expansion hub or town, the points inside it now fold into one icon on the compass instead of a crowd of service and quest icons. Click it to choose the place itself or any point inside it; once you walk in (where the minimap names the place), every point shows as usual, and in towns the points glide out of the icon as you enter and back into it as you leave. A town lists and shows every point inside it even beyond that point type's range; on Forever with QuestieDB that includes the quest givers and town services of a town across a zone border. Your current destination always keeps its own icon. Capitals and hubs each have their own icon (the six capitals on Forever, Stormwind to Dornogal on Retail); goblin towns such as Booty Bay, Gadgetzan, Ratchet and Everlook share a goblin icon, Horde towns such as Brill, the Crossroads or Camp Mojache an orcish hut, and other towns and quest hubs such as Goldshire a town icon. On Forever this covers about 70 towns, including every flight-master town. The other faction's capitals and towns are named in red and offer only the points inside them.
* Cities and towns are landmarks on the compass: they show within their own range even when none of their points do, and shrink with distance at half the rate of other icons. A new Cities & Towns row in Points turns them and the folding on or off for cities, the world and the toggle hotkey, and sets their range. While you are in a capital or hub, towns and their points stay off the compass. Face a city or town and its name and distance fade in beside the compass in the game's own lettering on a soft smoky backdrop, with a yellow ! before the name when it has quests you can pick up; Place Names under Appearance puts them above or below the compass, or turns them off.
* Compass has a Font option under Appearance that changes all Compass text, including the compass letters, the arrow and town names, without touching your Orbit font. Default follows your Orbit font, Blizzard uses the game's own font, and Compass's own fonts and any font your other addons share are listed too.
* Fixed: choosing a zone or city in Search no longer stops the compass drawing, and a map pin or rare you follow no longer fades away beyond its point type's range. With Orbit, the compass now pauses in vehicles and pet battles instead of leaving invisible points under your cursor. GatherMate nodes no longer overlap the compass letters, Alt's label no longer cuts a name short or skips a point beside the one you are tracking, and with Orbit Navigation the arrow no longer misses Arrived when the route step itself stays put.

## 2026-11-20

* On Forever with QuestieDB, Available Quests no longer shows quests no giver offers you: holiday quests, Season of Discovery-only and removed quests, the ended Ahn'Qiraj War Effort, battleground reputation turn-ins and similar event and reward quests.
* With Orbit Navigation, the compass shows how long it will take to reach your destination, based on your current speed.
* On Forever with QuestieDB, raid entrances use Blizzard's green raid icon. Hovering a dungeon or raid entrance shows its level, coloured for your level.

## 2026-11-19

* On Forever with QuestieDB, mailboxes now show under Town Services. Quest givers and town services are a little smaller, and innkeepers, mailboxes, repairers and stable masters have sharper icons.

## 2026-11-17

* With Orbit Navigation, the arrow now reads Arrived for a moment when you reach a destination and then fades out, and it stays hidden while you are inside your tracked quest's area. Hand-ins read Arrived at 8 yards instead of 15. Needs the matching Orbit Navigation update.
* On Forever with QuestieDB, objective icons no longer appear on Orbit's HUD map by themselves. Right-click a quest's pin there, or the quest in Orbit's Progress tracker, and choose Show Questie Hint to see where its unfinished objectives can be done; Hide Questie Hint removes them. A quest the game marks nowhere on the map keeps one icon to right-click. Needs the matching Orbit update.
* Quests that start from an item now appear on Orbit's HUD map as one quest marker where the item drops, following Available Quests. Its right-click shows or hides every place the item drops.
* Remove from the map now covers quest givers and turn-ins only.

## 2026-11-14

* Each point type in Points now has a thin range slider underneath it, so quest objectives, flight masters, rares and the rest can each appear from their own distance. Untouched sliders follow Marker Range in Behaviour (shown in grey); right-click a slider to return it to Marker Range.
* QuestieDB quest givers now respect your professions, known spells and specializations, and draw 25% smaller on Orbit's map. A quest is offered only once the game confirms it exists, so quests this version never had no longer appear.
* On Forever with QuestieDB installed, Orbit's HUD map shows where the unfinished objectives of quests in your log can be done when the game marks no area or pin for them, and the turn-in when a quest is complete. They follow the Quest Objectives point.
* Right-click a QuestieDB point on Orbit's HUD map for a menu that removes a quest from the map: its giver, objective icons and turn-in go, on the compass too. The same menu restores every removed quest.

## 2026-11-13

* With Orbit also installed, those quest givers appear on Orbit's HUD map too, following the Available Quests point.
* On Forever with QuestieDB installed, the compass shows quest givers with quests you can take, dungeon and raid entrances, and a new Town Services point type for innkeepers, repairers, bankers, auctioneers and stable masters. Hovering a quest giver lists its quests with their levels in difficulty colours. A Quest Level Range slider in Appearance (default 5) hides quests too far above or below your level.

## 2026-10-24

* On Forever with Orbit, herbs and ore spotted by the minimap now appear below the compass as round icons with thin gold borders. They follow Orbit's existing resource setting.

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
