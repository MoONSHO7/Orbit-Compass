# Compass search

## Description
A world-wide landmark index and the inline search field at the ribbon's bottom-left corner.

## Purpose
Let players find anything the world map lets them click, then track it through the same native super-tracking the map uses, so Blizzard's route shortcuts guide the arrow.

## Implementation
`Search.xml` loads `CompassMapScope.lua`, the index, ranking and the view. Scope validates bounded, cycle-free ancestry to Retail's Cosmic or Forever's World ancestor, using the player map, Blizzard's fallback seed, then a previously validated root. No fixed map number identifies a client.

`CompassLandmarkCatalog.lua` walks `C_Map.GetMapChildrenInfo(rootID, nil, true)` in a coroutine, stepped once per frame by `Compass.lua` or its demand driver. Search consumers acquire demand (focused field, Orbit session), allowing progress with the ribbon hidden or inside an instance. Listeners receive revisions every 0.25 s and on completion. Budgets are 1 ms, or 4 ms with focused demand. Walking starts on demand or for a tracked pin, refreshing after five minutes into a side table that replaces the live index only when complete. Policy-enabled collectors on each continent, zone and micro map contribute:
- area records;
- dungeon entrances and delves;
- events, races, quest hubs and generic area POIs, split into teleports by atlas;
- map links, split into caves;
- pet tamers and friendly taxi nodes;
- dig sites, task quests (world quests, world bosses, bonus objectives), graveyards and invasions.

This follows Blizzard's `MapLegendFrame.lua` categories. Records are frozen landmarks keyed like ribbon markers (`poi:`, `taxi:`, `digSite:`, `quest:`, `map:`) with folded name and place (zone, continent) text. `FindCompassLandmarkOnMap` reuses the collectors for world-map clicks.

`CompassLandmarkSearch.lua` searches into caller-owned scratch (`NewCompassSearchScratch`), recording a score and a match tier per result (5 exact to 1 typo/loose) so Orbit can merge places with its own results; `fuzzy = false` skips the fuzzy pass and `limit` trims the list. It adds live results at query time: quest-log quests, the current map's Compass markers (rares, treasures, quest offers, HandyNotes, GatherMate2), and saved locations, skipping anything the index already holds. Queries fold through `Addon.Text.Fold`. Category phrases come from English aliases, localized type labels, Blizzard's client-localized `MAP_LEGEND_*` names and the localized `PLU_COMPASS_SEARCH_ALIASES`. Matching is fuzzy and ranks by relevance, highest first:
- exact name, name prefix, word start, then substring (shorter names first);
- query words as prefixes of name or place words, in any order;
- category lists, where the last word of a phrase may be partial, so "dung" lists dungeons;
- a fuzzy pass, only when the strict pass fills fewer than twelve rows: typos within the typed prefix, then letters in order across the name.

`CompassSearchView.lua` owns the magnifier, the inline EditBox and the plain list below them, all in Orbit UI Chat. While another addon's LibOrbitSearch search includes places, such as Orbit's Spotlight, the magnifier and field hide entirely because that search already covers them (see `../Integrations/README.md`). Empty-input focus loss and hosted takeover release demand; close cancels pending typing and clearing text discards stale results. Typing is coalesced for 80 ms, and Enter, Tab and arrow keys flush a pending search first. Scrolling and highlighting repaint rows without searching again. Rows show icon, name and place; hover or arrow keys paint the name gold. The mouse wheel and arrow keys scroll the twelve visible rows. Choosing a continent narrows the query instead of tracking.

Optional `Services.profiler` spans attribute inline `Compass.Search.Build`, `Open`, `Query`, `Render`, `Close`, and each `Compass.Landmarks` coroutine resume. Catalog timing belongs to the catalog owner, so hidden-ribbon demand and visible-ribbon updates share coverage without duplicate spans. Without Orbit, the workspace performance runner can inject this service; native addon totals alone do not provide these detailed timings.

## Gotchas
- Missing roots/child-map data retry after one second; incomplete activity lists retry after 30 seconds. First-build valid entries remain searchable; refreshes preserve the previous index until complete. Changed roots retire old entries and cached pin destinations. Disable cancels jobs/listeners/demand; idle world entry does not start an unused index.
- Forever retains dungeon entrances with a neutral Instance label, without journal classification. World Quests/tasks, Delves, races, tamers, dig sites and invasions are withheld. Saved records require client provenance. Search remains independent of Points visibility so a supported explicit choice can still be tracked.
- Indexed selections require current catalog membership; live markers require current identity; saved choices reread their coordinates/provenance.
- Choice dispatch:
  - Map-pin landmarks track natively (`SetSuperTrackedMapPin`).
  - Quests are watched, then super-tracked (`compassQuestSelection` lets the quest source ignore hidden quest Points).
  - Live markers select exactly like a ribbon click.
  - Everything else, including refused pins, becomes a labelled user waypoint: zone centre, micro rect centre on its parent, or the recorded coordinates.
- A full-name match beats a category word, so a POI named with "portal" still matches by name.
- Category and place words match at word starts only; mid-word matches are reserved for the full query against names. Partial category words need three letters, and typos need four letters (one edit, two from seven letters). A typo must keep the word's first letter. Repeated word/target typo comparisons share a query-local cache, discarded after the fuzzy pass; ranking is unchanged. Workspace `develop/search-bridge/search_performance.py` compares cached/uncached costs and ordering on a synthetic 6,000-entry corpus.
- Phased map copies with the same name and parent collapse to the first. A POI ID seen on several maps keeps the primary or deepest map's record, and task quests prefer their own map (`childDepth`).
- After the walk, same-name entries collapse when one sits on an ancestor or continent map of the other, or within 100 yards in world space. Parent maps repeat places under other POI IDs that do not route. Same-name places elsewhere stay distinct, and quests are excluded.
- Quest offers, rares and treasures exist only near the player, so they come from live markers, not the index. The index is session-only and never persisted.
- There is no placeholder text: only the magnifier shows until the field is focused. Search elements sit at ribbon level +27, above markers (1–24), badges (25) and the Alt callout (26). Edit Mode hides them; hiding the ribbon or clicking elsewhere closes the list and clears the query.

## Secrets
Native map, POI, quest, journal, graveyard and taxi records pass through `SourceUtils.Readable`/`Number` before comparison or arithmetic. Folding uses explicit byte ranges because locale-aware `string.lower` and `%s`/`%p` classes can rewrite UTF-8 bytes.

## References
`../Navigation/README.md` (tracking and destination resolution), `../Discovery/README.md`, `../Foundation/README.md`; Blizzard `MapLegendFrame.lua`, `SharedMapPoiTemplates.lua`, `WorldQuestDataProvider.lua`, `DungeonEntranceDataProvider.lua` and generated `MapDocumentation.lua` / `QuestTaskInfoDocumentation.lua`.
