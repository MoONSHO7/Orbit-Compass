# Native point sources

## Description
Collectors for Blizzard map, quest, travel and tracked-content points.

## Purpose
Keep native provider contracts separate from discovery scheduling and optional-addon adapters.

## Implementation
`Sources.xml` loads travel, tracked-content, quest-offer, map and watched-quest collectors. They append validated records through `../CompassSourceUtils.lua`; `../CompassDiscovery.lua` owns when they run and when completed snapshots become visible.

`CompassTravelSources.lua` covers native route steps, directions, map links, pet tamers and dig sites. `CompassContentSources.lua` resolves tracked content. `CompassOfferSources.lua` merges quest lines, forced-visible quests and task offers. `CompassMapSources.lua` handles map POIs, taxi nodes and vignettes; `CompassQuestSources.lua` owns watched objectives and targeted route refreshes.

## Gotchas
- Client policy gates nested map categories, quest tasks/watch lists, offer classifications and route types. Forever withholds World Quests/tasks, races, tamers, archaeology, Delves and tracked content; explicit selection cannot enable them.
- Dungeon entrances use their native provider independently of Encounter Journal classification. Generic native POIs have no documented activity discriminator: beta must verify that withheld activities do not leak through generic lists.
- Complete map POIs remain cached until native POI/quest-hub updates or a context reset. Timed points schedule expiry checks; incomplete data schedules retries.
- Quest-offer deduplication precedes visibility filtering so earlier records remain authoritative. Task coordinates belong to the queried map. Retail retains all offer classifications and native filters. Forever initially accepts Normal, Questline and Important offers only; Recurring, Meta, Calling, Campaign and Legendary await beta verification.
- `SUPER_TRACKING_PATH_UPDATED` can repeat while navigating. Refresh only the supertracked quest through the budgeted queue, retaining other markers and the full-scan deadline. Unusable coordinates skip quest metadata reads but retain map/task fallback.
- Route steps come from `C_Navigation.GetNextWaypointForMap` for super-tracked user waypoints, followed map pins, content and
  vignettes. The step is one hop in current-map coordinates; quests keep their own per-quest waypoint query.
- A route step shows the travel arrow when its destination is projectable onto the current map, and otherwise borrows the
  destination's name and artwork so a cross-continent trip still shows what it leads to.
- A quest chosen through Search (`compassQuestSelection`) is collected even when quest or world-quest Points are hidden, like other explicit selections.
- `Compass.Discovery.QuestWaypoint` measures individual native waypoint queries; it never spans a discovery yield. Fixed counters distinguish accepted/rejected quest positions and targeted-path fallbacks.
- Saved locations and corpse guidance remain in Navigation; HandyNotes remains in Integrations. They are source consumers of the scheduler, not native provider implementations.

## Secrets
Use the shared source boundary before inspecting native IDs, positions or records. Quest coordinates use its finite-number policy, including finite points outside 0..1; a range restriction would change existing marker behavior.

## References
`../README.md`, `../../Navigation/README.md`, `../../Integrations/README.md`; authoritative Blizzard sources under workspace `wow-ui-source/`.
