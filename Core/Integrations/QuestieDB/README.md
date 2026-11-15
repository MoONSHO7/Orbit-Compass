# QuestieDB integration

## Description
Forever-only quest givers, town services, instance entrances and quest-log objectives read from an installed QuestieDB
at runtime.

## Purpose
Forever's client exposes no available-quest givers, service locations, journal entrances or objective locations to
addons; its minimap draws quest givers natively. QuestieDB carries that data, so Compass reads it when the player has
it installed.

## Implementation
`QuestieDB.xml` loads ten files. `CompassQuestieIndex.lua` admits the provider (`LibQuestieDB.RequireContract(4)`,
every entity read used) and builds one per-UiMap index: quest starters from each quest's `startedBy` (so the object
table is never swept), NPCs whose flags mark an innkeeper, repairer, banker, auctioneer or stable master, and instance
entrances. The build runs on its own driver frame within 0.5 ms per frame, outside discovery's single job slot, then
invalidates the `questie` source; disabling Compass pauses it and the next request resumes it.
`CompassQuestieAvailability.lua` decides whether a quest is available; decoded quest rows stay in the index's session
cache and verdicts in a per-collection context. A quest that passes is still shown only once
`CompassQuestieExistence.lua` has the game's word that it exists: cached client data, or the answer to one
`C_QuestLog.RequestLoadQuestByID` (eight a tenth of a second, each quest asked once a session). `CompassQuestieDB.lua` is the `questie` discovery collector
(`../../Discovery/CompassDiscoveryCatalog.lua`): it reads the player's map, its direct child maps and its parent zone,
projects each point onto the player's map and publishes `questOffer`, `service` and `poi` markers. They follow the
Available Quests, Town Services and Zone POIs points. Their tooltip lines (`CompassQuestieLines.lua`) list a giver's
available quests as "[level] title" in `GetQuestDifficultyColor`'s colour, a service's tracking roles, or the instance
label; one summary per giver is shared by its spawns within a collection.

The collector also answers a host's map (`CollectCompassQuestieMapRows`, `../Orbit/README.md`) with one UI map's
givers, then the quest log's rows under the Quest Objectives point. `CompassQuestieLog.lua` snapshots the log through
`C_QuestLog` (entries, live objectives, completion). `CompassQuestieObjectives.lua` turns a quest's QuestieDB row into
a plan in the client's objective order and clusters where each part can be done on a map: a creature's or object's
spawns, an item's droppers and containers (vendors only without either), a kill credit's listed NPCs, the `triggerEnd`
point and the `finishedBy` spawns. `CompassQuestieLogRows.lua` matches plan and live list by index, skips finished
objectives, shows a complete quest (or one with no objectives at all) as its turn-in instead, and builds the rows.
Every row names the quests it stands for (`CompassQuestieMenu.lua`, per collected map, eight maps kept) and carries
the host's right-click hint; the host's menu then lists those quests under Remove from the map.
`CompassQuestieHidden.lua` holds the removed quests, which lose their giver offer, objective icons and turn-in on the
map and the ribbon until the menu's restore row clears the list.

Bounds. Only the objectives driver reads QuestieDB tables, within 0.5 ms per frame and once per session: one plan per
log quest and one spawn list per source (at most 16 sources per item or kill credit). Per viewed map it keeps at most
24 spots per objective, one per occupied 2.5% grid cell at the cell's mean position, densest first, and 4 per
finisher. A collection reads no QuestieDB table: it queues and skips unprepared quests, visits at most 24 cached spots
per unfinished objective, publishes at most 240 turn-in and objective icons per map (trimmed evenly across
objectives), and reads the client's quest pins once when a log quest has places: a quest the client pins on that map
draws no objective icons (its own pin or area is there) and a turn-in beside its pin is dropped. The driver
invalidates the host once, and
only when it found a place. With the optional Orbit profiler active the two drivers and the coalesced log read are
timed as `Compass.QuestieDB.Index`, `.Prepare` and `.Log`, with `QuestieDB/Log/Event`, `Changed` and `Unchanged` counts.

## Gotchas
- QuestieDB is never bundled or copied: its licence does not allow it here. Compass reads the installed copy only, and
  without it (or with an older contract, or without its item reads) the source stays pending or empty.
- QuestieDB supplies data, not quest logic. Availability is ours: completion, quest log, level, race and class masks,
  prerequisites (a single prerequisite stands in for a group; a group member also counts once a quest exclusive
  to it was done), exclusive and breadcrumb links both ways, parent and chain quests, reputation and the Quest
  Level Range (default 5; quests further above or below the character's level stay hidden), which replaces the native
  trivial rule; a higher quest still needs its required level.
  The slider renders only while a compatible QuestieDB is loaded on Forever. `requiredSkill` and any one
  `requiredRanks` alternative are confirmed through `C_SkillInfo.GetSkillLineInfoByID`: a client without that reader,
  or a skill never learned, keeps the quest hidden. `requiredSpell` and `requiredSpecialization` use
  `C_SpellBook.IsSpellKnown`; a negative spell ID is one the character must not know. Only holiday-category quests
  stay hidden because they cannot be confirmed. `specialFlags` bit 2 describes completion by exploration or a
  scripted event, not availability, so it never hides a quest.
- Questie's own hidden-quest and NPC blacklists are Questie policy that QuestieDB does not ship, and nothing of them
  is copied. Instead a quest draws only after the game confirms it (`QUEST_DATA_LOAD_RESULT`); one it denies or
  never answers stays hidden, as does a title carrying Blizzard's retired markers (UNUSED, DEPRECATED, <NYI>...).
  Denials count only once some quest was confirmed: a client that confirms nothing within five seconds hides
  none. A quest the server knows but its giver never offers can still appear; Forever-new quests missing from
  QuestieDB never show.
- Removed quests are per character in the host plugin's CharData (`QuestieRemovedQuests`); a host without that door
  keeps them for the session only. A removal acts on the quest, not the pin: a giver stays while it offers another.
- Race masks exceed 32 bits; `Index.HasBit` uses arithmetic, never the `bit` library.
- QuestieDB's dungeon table carries later expansions' entrances. An instance counts only when `GetRealZoneText` names
  its map on this client, which also gives the localized name. Native journal entrances win per map when the client
  returns any; an unreadable native answer leaves QuestieDB's entrances shown.
- Service icons and names come from the client's minimap tracking list, so they stay Blizzard art and localized.
  QuestieDB has no trainer class, so trainers are not shown.
- Its area-to-UiMap table is Lua source by contract; it runs under an empty environment inside one protected call. A
  failing build step stops the driver for the session and reports once through the error handler. A log quest whose
  data fails is dropped for that map and reported once; the other quests still prepare.
- Scanning every NPC's flags fills QuestieDB's per-entity read cache for the session; measure its heap in-game.
- Quest accept, turn-in, abandon, level-up and Quest Level Range changes refresh the source; reputation and skill
  changes wait for the 60-second refresh. Same-map subzone moves keep a ready snapshot.
- Objective order is QuestieDB's (creature, object, item, reputation, kill credit, spell, then the trigger) unless its
  `ObjectiveFirst` hints name the group a quest lists first. When the client's list differs in count or type, every
  located objective shows under QuestieDB's names rather than none. Reputation and spell objectives, `extraObjectives`,
  source items, spawn phases and instance interiors (QuestieDB gives those no coordinates) are not drawn.
- Objective icons draw at 0.6 scale in Blizzard art only: the item's own icon (`C_Item.GetItemIconByID`), else the
  client's interaction art (`Crosshair_attack_32`, `Crosshair_interact_32`, `Crosshair_lootall_32`) and `VignetteEvent`
  for a trigger. Each is probed with `C_Texture.GetAtlasInfo` and falls back to `Bonus-Objective-Star`. A turn-in uses
  `UI-QuestIcon-TurnIn-Normal` at the client pin's size. Forever 1.60.1.70938's atlas table and art hold all of them;
  their look on the map is unverified in-game.
- Spots in one cell that share a source merge into one icon, so two quests on the same creature do not stack. The
  group's first objective by quest and index owns its key (`objective:<quest>:<index>:<cell>`), place, icon and title;
  the tooltip has one section per quest (title, live objective text, sources that are not the objective itself) and
  keeps whole sections within the host's 16 lines.
- A QuestieDB turn-in within 0.03 of the map (about one icon) of a point `C_QuestLog.GetQuestsOnMap` reports for that
  quest is left to the client's own pin. NPC finishers must serve the player's faction.
- `QUEST_LOG_UPDATE` and `QUEST_POI_UPDATE` arrive in bursts: the log is read once, 0.25 s after the first event, and
  the host is invalidated only when the log changed or a pin moved while the log holds a quest. Accept, turn-in,
  abandon, level-up and world entry make the next collection read anew. A snapshot older than 30 s is read again, so
  the host's 60-second refresh is the backstop; after 90 s without a collection bursts stop reading the log.

## Secrets
Quest-log, map, item and unit reads pass `SourceUtils.Readable`, `Number` or `Text` before any comparison or
arithmetic. QuestieDB's tables are addon data and are only shape-checked.

## References
`../README.md`, `../Orbit/README.md`, `../../Discovery/README.md`, QuestieDB `docs/api.md` (contract 4: entity reads,
nil semantics, `Enum.npcFlags`/`classKeys`/`raceMaskById`, Support data), its `Types/*.t.lua` (objective, trigger and
giver tuples, `ObjectiveFirst`) and `DESIGN.md` (consumer-owned policy). Blizzard `QuestOfferDataProvider.lua`,
`DifficultyUtil.lua`, `POIButton.lua` (turn-in art) and generated `QuestLogDocumentation.lua` on Forever and Retail.
