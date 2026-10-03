# Compass search

## Description
A world-wide landmark index and the inline search field at the ribbon's bottom-left corner.

## Purpose
Let players find anything the world map lets them click, then track it through the same native super-tracking the map
uses, so Blizzard's route shortcuts guide the arrow.

## Implementation
- **Scope.** `Search.xml` loads `CompassMapScope.lua`, the index, ranking and the view. Scope validates bounded,
  cycle-free ancestry to Retail's Cosmic or Forever's World ancestor, using the player map, Blizzard's fallback seed,
  then a previously validated root. No fixed map number identifies a client.
- **Index.** `CompassLandmarkCatalog.lua` walks `C_Map.GetMapChildrenInfo(rootID, nil, true)` in a coroutine stepped
  only by its demand driver. Demand owners are the focused inline field (or its list while shown), an Orbit search
  session from its first scored query (two folded characters, `IsScoredCompassQuery`, the ranker's own predicate), and a
  tracked map pin that the search choice, the open world map and the index cannot resolve. Without demand, requests and
  world entry only re-resolve and retire the root; release pauses the walk and the next acquire resumes it. Listeners
  receive revisions every 0.25 s and on completion. Budgets are 1 ms, or 4 ms with focused demand. Under demand, an
  index older than five minutes refreshes into a side table that replaces the live index only when complete. The walk's
  child-copy, duplicate comparison/compaction and query-entry loops check that budget per record; native child-map
  retrieval and the final folded-name concatenation remain indivisible. Final steps build a query index (word postings,
  a folded-name blob and kind lists) and publish it with
  the entries in one step, except after an incomplete refresh; a root change or a build into the live index clears it,
  so none exists while a first build runs.
- **Collectors.** Policy-enabled collectors on each continent, zone and micro map contribute area records; dungeon
  entrances and delves; events, races, quest hubs and generic area POIs, split into teleports by atlas; map links, split
  into caves; pet tamers and friendly taxi nodes; dig sites, task quests (world quests, world bosses, bonus objectives),
  graveyards and invasions. This follows Blizzard's `MapLegendFrame.lua` categories. Records are frozen landmarks keyed
  like ribbon markers (`poi:`, `taxi:`, `digSite:`, `quest:`, `map:`); only a record that wins its key gets folded name
  text, and each distinct place (zone, continent) is folded once per walk into read-only words shared by its records.
  `FindCompassLandmarkOnMap` reuses the collectors for world-map clicks.
- **Ranking.** `CompassLandmarkSearch.lua` searches into caller-owned scratch (`NewCompassSearchScratch`), recording a
  score and a match tier per result (5 exact to 1 typo/loose) so Orbit can merge places with its own results;
  `fuzzy = false` skips the fuzzy pass and `limit` trims the list. It adds live results at query time (quest-log quests,
  the current map's Compass markers such as rares, treasures, quest offers, HandyNotes and GatherMate2, and saved
  locations), skipping anything the index already holds. Queries fold through `Addon.Text.Fold`. With a query index each
  pass scores only its candidates, visited in entry order so results and ties equal a full scan; without one it scans
  every entry. Category phrases come from English aliases, localized type labels, Blizzard's client-localized
  `MAP_LEGEND_*` names and the localized `PLU_COMPASS_SEARCH_ALIASES`. Relevance order, highest first: exact name, name
  prefix, word start, then substring (shorter names first); query words as prefixes of name or place words, in any
  order; category lists, where the last word of a phrase may be partial, so "dung" lists dungeons; and a fuzzy pass only
  when the strict pass fills fewer than twelve rows (typos within the typed prefix, then letters in order across the
  name).
- **View.** `CompassSearchView.lua` owns the magnifier, the inline EditBox and the plain list below them, all in Orbit
  UI Chat. While another addon's LibOrbitSearch search includes places, such as Orbit's Spotlight, the magnifier and
  field hide entirely because that search already covers them (see `../Integrations/README.md`). Empty-input focus loss
  and hosted takeover release demand; close cancels pending typing and clearing text discards stale results. Typing is
  coalesced for 80 ms, and Enter, Tab and arrow keys flush a pending search first. Scrolling and highlighting repaint
  rows without searching again. Rows show icon, name and place; hover or arrow keys paint the name gold; the mouse wheel
  and arrow keys scroll the twelve visible rows. Choosing a continent narrows the query instead of tracking.
- **Profiling.** Optional `Services.profiler` spans attribute `Compass.Search.Build`, `Open`, `Query`, `Render`, `Close`
  and each `Compass.Landmarks` resume. Fixed nested phases separate child retrieval/copy, collection, duplicate
  grouping/comparison/compaction and query entries/blob; the step owner closes phases on yield, completion or failure.
  Standalone needs a supplied profiler service; native addon totals alone do not give these timings.

## Gotchas
- Missing roots/child-map data retry after one second; incomplete activity lists retry after 30 seconds; both retries
  run only while demand holds. First-build valid entries remain searchable; refreshes preserve the previous index until
  complete; the query index must index exactly the published entries, candidates must be visited in entry order, and
  `MarkCandidates` must stay a superset of every `Score` branch. Replacing a resolved root retires old entries, cached
  pin destinations and the pin attempt. Disable cancels jobs/listeners/demand; world entry never starts or refreshes an
  index and pauses pin work.
- A tracked pin drives at most one finished walk per pin and root (`pinAttempted`), so a hostile, withheld or
  dedup-removed pin cannot restart the world walk. It pauses whenever the ribbon stops updating (profile suppression,
  hidden UIParent, standalone pet battle/vehicle, instance, loading screen; Orbit alpha fades keep it updating), and the
  pause marks waypoints dirty so the next visible rebuild re-requests the pin and resumes the walk.
- Forever retains dungeon entrances with a neutral Instance label, without journal classification. World Quests/tasks,
  Delves, races, tamers, dig sites and invasions are withheld. Saved records require client provenance. Search remains
  independent of Points visibility so a supported explicit choice can still be tracked.
- Indexed selections require current catalog membership; live markers require current identity, and their search rows
  are reused by marker identity, so never change a published marker's `kind`, `key`, `name`, `atlas` or art fields
  (replace the marker instead); saved choices reread their coordinates/provenance.
- Choice dispatch: map-pin landmarks track natively (`SetSuperTrackedMapPin`); quests are watched, then super-tracked
  (`compassQuestSelection` lets the quest source ignore hidden quest Points); live markers select exactly like a ribbon
  click; everything else, including refused pins, becomes a labelled user waypoint at the zone centre, the micro rect
  centre on its parent, or the recorded coordinates.
- A full-name match beats a category word, so a POI named with "portal" still matches by name.
- Category and place words match at word starts only; mid-word matches are reserved for the full query against names.
  Partial category words need three letters (`MIN_PARTIAL_LENGTH`), and typos need four (`TYPO_MIN_LENGTH`; one edit,
  two from seven letters). A typo must keep the word's first letter. Repeated word/target typo comparisons share a
  query-local cache, discarded after the fuzzy pass; ranking is unchanged.
- Phased map copies with the same name and parent collapse to the first. A POI ID seen on several maps keeps the primary
  or deepest map's record, and task quests prefer their own map (`childDepth`).
- After the walk, same-name entries collapse when one sits on an ancestor or continent map of the other, or within 100
  yards in world space. Parent maps repeat places under other POI IDs that do not route. Same-name places elsewhere stay
  distinct, and quests are excluded.
- Quest offers, rares and treasures exist only near the player, so they come from live markers, not the index. The index
  is session-only and never persisted.
- There is no placeholder text: only the magnifier shows until the field is focused. Search elements sit at ribbon level
  +27, above markers (1–24), badges (25) and the Alt callout (26). Edit Mode hides them; hiding the ribbon or clicking
  elsewhere closes the list and clears the query.

## Secrets
Native map, POI, quest, journal, graveyard and taxi records pass through `SourceUtils.Readable`/`Number` before
comparison or arithmetic. Folding uses explicit byte ranges because locale-aware `string.lower` and `%s`/`%p` classes
can rewrite UTF-8 bytes.

## References
`../Navigation/README.md` (tracking and destination resolution), `../Discovery/README.md`, `../Foundation/README.md`,
`../Integrations/README.md` (the LibOrbitSearch provider); Blizzard `MapLegendFrame.lua`, `SharedMapPoiTemplates.lua`,
`WorldQuestDataProvider.lua`, `DungeonEntranceDataProvider.lua` and generated `MapDocumentation.lua` /
`QuestTaskInfoDocumentation.lua`.
