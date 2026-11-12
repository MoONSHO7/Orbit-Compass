# QuestieDB integration

## Description
Forever-only quest givers, town services and instance entrances read from an installed QuestieDB at runtime.

## Purpose
Forever's client exposes no available-quest givers, service locations or journal entrances to addons; its minimap draws
quest givers natively. QuestieDB carries that data, so Compass reads it when the player has it installed.

## Implementation
`QuestieDB.xml` loads three files. `CompassQuestieIndex.lua` admits the provider (`LibQuestieDB.RequireContract(4)`,
every entity read used) and builds one per-UiMap index: quest starters from each quest's `startedBy` (so the object
table is never swept), NPCs whose flags mark an innkeeper, repairer, banker, auctioneer or stable master, and instance
entrances. The build runs on its own driver frame within 0.5 ms per frame, outside discovery's single job slot, then
invalidates the `questie` source; disabling Compass pauses it and the next request resumes it.
`CompassQuestieAvailability.lua` decides whether a quest is available; decoded quest rows stay in the index's session
cache and verdicts in a per-collection context. `CompassQuestieDB.lua` is the `questie` discovery collector
(`../../Discovery/CompassDiscoveryCatalog.lua`): it reads the player's map, its direct child maps and its parent zone,
projects each point onto the player's map and publishes `questOffer`, `service` and `poi` markers. They follow the
Available Quests, Town Services and Zone POIs points. Their tooltip lines list a giver's available quests as
"[level] title" in `GetQuestDifficultyColor`'s colour, a service's tracking roles, or the instance label; one summary
per giver is shared by its spawns within a collection.

## Gotchas
- QuestieDB is never bundled or copied: its licence does not allow it here. Compass reads the installed copy only, and
  without it (or with an older contract) the source stays pending or empty.
- QuestieDB supplies data, not quest logic. Availability is ours: completion, quest log, level, race and class masks,
  prerequisites, exclusive and breadcrumb links, parent and chain quests, reputation and the Appearance tab's Quest
  Level Range (default 5; quests further above or below the character's level stay hidden), which replaces the native
  trivial rule; a higher quest still needs its required level.
  The slider renders only while a compatible QuestieDB is loaded on Forever. Skill, spell, specialization, rank and
  holiday-category quests stay hidden because they cannot be confirmed. `specialFlags` bit 2 describes completion by
  exploration or a scripted event, not availability, so it never hides a quest.
- Questie's own hidden-quest and NPC blacklists are Questie policy that QuestieDB does not ship, so givers for quests
  Questie hides can appear; Forever-new quests missing from QuestieDB never show.
- Race masks exceed 32 bits; `Index.HasBit` uses arithmetic, never the `bit` library.
- QuestieDB's dungeon table carries later expansions' entrances. An instance counts only when `GetRealZoneText` names
  its map on this client, which also gives the localized name. Native journal entrances win per map when the client
  returns any; an unreadable native answer leaves QuestieDB's entrances shown.
- Service icons and names come from the client's minimap tracking list, so they stay Blizzard art and localized.
  QuestieDB has no trainer class, so trainers are not shown.
- Its area-to-UiMap table is Lua source by contract; it runs under an empty environment inside one protected call. A
  failing build step stops the driver for the session and reports once through the error handler.
- Scanning every NPC's flags fills QuestieDB's per-entity read cache for the session; measure its heap in-game.
- Quest accept, turn-in, abandon, level-up and Quest Level Range changes refresh the source; reputation waits for the
  60-second refresh. Same-map subzone moves keep a ready snapshot.

## References
`../README.md`, `../../Discovery/README.md`, QuestieDB `docs/api.md` (contract 4: entity reads, nil semantics,
`Enum.npcFlags`/`classKeys`/`raceMaskById`, Support data) and `DESIGN.md` (consumer-owned policy). Blizzard
`QuestOfferDataProvider.lua` and `DifficultyUtil.lua` (Forever and Retail) for the native offer and difficulty rules.
