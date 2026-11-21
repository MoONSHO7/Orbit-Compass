# QuestieDB integration

## Description
Forever-only quest givers, town services, instance entrances and quest-log objectives drawn from an installed
QuestieDB, read and cleaned by the embedded LibOrbitBridge.

## Purpose
Forever's client exposes no available-quest givers, service locations, journal entrances or objective locations to
addons; its minimap draws quest givers natively. QuestieDB carries that data, so Compass shows it when the player has
it installed. LibOrbitBridge owns reading and cleaning it; this module owns how Compass presents it.

## Implementation
`QuestieDB.xml` loads six files. The bridge (`Libs/LibOrbitBridge-1.0`, contract in its README) admits the provider,
builds the per-UiMap index, decides availability (including its curated list of quests no Forever giver offers and the
game's existence check), plans objectives and snapshots the log. `CompassQuestieDB.lua` is the `questie` discovery
collector (`../../Discovery/CompassDiscoveryCatalog.lua`): it reads the player's map, its direct child maps and its
parent zone, plus only the points inside other maps' nearby towns (`GetCompassTownMaps`, so a town across a zone border
lists its givers and services), projects each point onto the player's map and publishes `questOffer`, `service` and
`poi` markers under the Available Quests, Town Services and Zone POIs points. `ConnectCompassQuestie` registers the
bridge's callbacks (index ready refreshes the source; existence, places and, with Quest Objectives shown, log changes
invalidate the host's map) and its profiler; `DisconnectCompassQuestie` releases Compass's demand. Tooltip lines (`CompassQuestieLines.lua`) list
a giver's quests as "[level] title" in `GetQuestDifficultyColor`'s colour, a service's tracking roles or the instance
label and, from the group finder lists `CompassQuestieInstances.lua` reads once a collection, its suggested levels.

The collector also answers a host's map (`CollectCompassQuestieMapRows`, `../Orbit/README.md`) with one UI map's
givers, then the quest log's rows under the Quest Objectives point. `CompassQuestieLogRows.lua` builds the rows from the
bridge's log snapshot and plans: a complete quest (or one with no objectives at all) as its turn-in, a hinted quest as
its unfinished objectives. No hint shows until asked for, so something must take the right-click that asks:
`CompassQuestieMenu.lua` answers the host's `QuestHint`/`QuestMenu` for a log quest whose plan places an objective it
still needs (its own pin or tracker row), and a quest the client pins nowhere on the map keeps one icon, the densest
spot of its first unfinished objective. An available quest an item starts is drawn as one `!` at the densest spot of
its drops, or at every spot once hinted. Every row names its quests (per collected map, eight maps kept) under the
host's right-click hint: its menu shows or hides their hints and, for a giver, a dropped start or a turn-in, lists them
under Remove from the map. `CompassQuestieHidden.lua` holds both lists: hinted quests, and removed ones, which the
collector passes to the bridge's availability context so they lose their giver offer and turn-in until the menu's
restore row clears the list.

Bounds. A collection reads no spawn table: it queues unprepared quests with the bridge and skips them, visits at most 24
cached spots per unfinished objective of a hinted quest, publishes at most 240 turn-in and objective icons and 120
dropped-start icons per map, and reads the client's quest pins once: a turn-in beside its quest's pin is dropped, and an
unhinted quest with a pin there draws nothing. It walks every item-started quest but decodes only those inside the
Quest Level Range. Every log quest is prepared, hinted or not: its plan decides whether the host offers a hint, which a
hover asks of the cached log and plan only.

## Gotchas
- QuestieDB is never bundled or copied: its licence does not allow it here. Without it (or with an older contract, or
  without its item reads) the source stays pending or empty. The Quest Level Range slider (default 5) renders only
  while a compatible QuestieDB is loaded on Forever.
- Wrong quests on the map are a bridge fix: add evidence-backed IDs to LibOrbitBridge's curated list or correct its
  availability rules, never a Compass-side filter, so every consumer agrees.
- Removed and hinted quests are per character in the host plugin's CharData (`QuestieRemovedQuests`,
  `QuestieHintQuests`); a host without that door keeps them for the session only. A removal acts on the quest, not the
  pin: a giver stays while it offers another, and a shown hint stays. Showing a hint drops those of quests completed
  since. One list serves both kinds, so a hint shown on a dropped start carries into the quest's objectives. Until
  2026-11-17 every log quest the client did not pin drew all its icons; the user asked for one, the rest on request.
- A dropped start is no giver: it draws on the host's map only, not the ribbon; its droppers face no faction rule.
- QuestieDB's dungeon table carries later expansions' entrances; the bridge keeps one only when `GetRealZoneText` names
  its map here. Native journal entrances win per map; an unreadable answer leaves QuestieDB's shown. A map only
  Forever's raid category (114) lists draws `Raid` art: the client also lists raid versions of dungeons.
- Service names come from the client's minimap tracking list (localized); its 32px icons stay for bankers and
  auctioneers, while the other services draw Blizzard's 64px `crosshair_*_64` art, the envelope through a centring
  texture window. QuestieDB has no object type: a mailbox is an object named "Mailbox" or the list's Mailbox name.
- Ribbon givers and services draw at 0.8: their art fills 81-97% of its box, `Dungeon` about 74% (measured 2026-11-19).
- Quest accept, turn-in, abandon, level-up and Quest Level Range changes refresh the source through discovery's own
  events; reputation and skill changes wait for the 60-second refresh. Same-map subzone moves keep a ready snapshot.
- Objective icons draw at 0.6 scale in Blizzard art only: the item's own icon (`C_Item.GetItemIconByID`, cached for the
  session), else the client's interaction art (`Crosshair_attack_32`, `Crosshair_interact_32`, `Crosshair_lootall_32`)
  and `VignetteEvent` for a trigger. Each is probed with `C_Texture.GetAtlasInfo` and falls back to
  `Bonus-Objective-Star`. A turn-in uses `UI-QuestIcon-TurnIn-Normal` at the client pin's size; Forever 1.60.1.70938
  holds all of them. Reputation and spell objectives, `extraObjectives`, source items, spawn phases and instance
  interiors (QuestieDB gives those no coordinates) are not drawn.
- Spots in one cell that share a source merge into one icon, so two quests on the same creature do not stack. The
  group's first objective by quest and index owns its key (`objective:<quest>:<index>:<cell>`), place, icon and title;
  the tooltip has one section per quest (title, live objective text, sources that are not the objective itself) and
  keeps whole sections within the host's 16 lines.
- A QuestieDB turn-in within 0.03 of the map (about one icon) of a point `C_QuestLog.GetQuestsOnMap` reports for that
  quest is left to the client's own pin. NPC finishers must serve the player's faction.

## Secrets
Quest-log, map, item and unit reads pass `SourceUtils.Readable`, `Number` or `Text` before any comparison or
arithmetic; the bridge guards its own reads the same way. QuestieDB's tables are addon data and are only shape-checked.

## References
`../README.md`, `../Orbit/README.md`, `../../Discovery/README.md`, Orbit-Libs
`LibOrbitBridge/LibOrbitBridge-1.0/README.md` (index, availability, curated list, plans, log), QuestieDB `docs/api.md`
(contract 4). Blizzard `QuestOfferDataProvider.lua`, `DifficultyUtil.lua`, `POIButton.lua` (turn-in art) on Forever and
Retail.
