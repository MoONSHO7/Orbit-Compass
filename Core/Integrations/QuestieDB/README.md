# QuestieDB integration

## Description
Forever-only quest givers, town services and instance entrances read from an installed QuestieDB at runtime.

## Purpose
Forever's client exposes no available-quest givers, service locations or journal entrances to addons; its minimap draws
quest givers natively. QuestieDB carries that data, so Compass reads it when the player has it installed.

## Implementation
`QuestieDB.xml` loads three files. `CompassQuestieIndex.lua` admits the provider (`LibQuestieDB.RequireContract(4)`,
every entity read used) and builds one per-UiMap index of NPC and object quest starters, NPCs whose flags mark an
innkeeper, repairer, banker, auctioneer or stable master, and instance entrances. The build yields through the
discovery checkpoint, resumes after a cancelled job and is kept on the controller for the session.
`CompassQuestieAvailability.lua` decides per collection whether a quest is available to the character.
`CompassQuestieDB.lua` is the `questie` discovery collector (`../../Discovery/CompassDiscoveryCatalog.lua`): it reads
the player's map, its direct child maps and its parent zone, projects each point onto the player's map and publishes
`questOffer`, `service` and `poi` markers. They follow the Available Quests, Town Services and Zone POIs points.

## Gotchas
- QuestieDB is never bundled or copied: its licence does not allow it here. Compass reads the installed copy only, and
  without it (or with an older contract) the source stays pending or empty.
- QuestieDB supplies data, not quest logic. Availability is ours: completion, quest log, level, race and class masks,
  prerequisites, exclusive and breadcrumb links, parent and chain quests, reputation and the native trivial rule
  (`UnitQuestTrivialLevelRange`, shown only with hidden-quest tracking). Skill, spell, specialization, rank, event and
  holiday quests stay hidden because they cannot be confirmed. Forever-new quests missing from QuestieDB never show.
- Race masks exceed 32 bits; `Index.HasBit` uses arithmetic, never the `bit` library.
- QuestieDB's dungeon table carries later expansions' entrances. An instance counts only when `GetRealZoneText` names
  its map on this client, which also gives the localized name. Native journal entrances win when the client has any.
- Service icons and names come from the client's minimap tracking list, so they stay Blizzard art and localized.
  QuestieDB has no trainer class, so trainers are not shown.
- Its area-to-UiMap table is Lua source by contract; it runs under an empty environment inside one protected call.
- Quest accept, turn-in, abandon, level-up and tracking changes refresh the source; reputation waits for the
  60-second refresh.

## References
`../README.md`, `../../Discovery/README.md`, QuestieDB `docs/api.md` (contract 4: entity reads, nil semantics,
`Enum.npcFlags`/`classKeys`/`raceMaskById`, Support data). Blizzard `QuestOfferDataProvider.lua` and
`DifficultyUtil.lua` (Forever and Retail) for the native offer and trivial rules.
