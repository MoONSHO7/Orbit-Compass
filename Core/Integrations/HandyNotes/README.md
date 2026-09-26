# HandyNotes integration

## Description
HandyNotes provider snapshots, note text, native tooltips and selected guide points.

## Purpose
Expose map notes as compass destinations while preserving provider identity and avoiding repeated scans of static data.

## Implementation
`HandyNotes.xml` declares the family readers and click adapter before the collector and tooltip adapter. `CompassHandyNotes.lua` caches enabled `GetNodes2` providers for the current map context. `CompassHandyNotesZarillion.lua` owns that family's exact identities and artwork; `CompassHandyNotesText.lua` owns shared successful-name caching and Zarillion's numbered instructions. `CompassHandyNotesKemayo.lua` reads 25 verified Kemayo identities from iterator metadata, including shared-handler rewards, legacy items, Directions names and Lorewalkers criteria.

`CompassHandyNotesClick.lua` captures and invokes explicit native left-click actions. `CompassHandyNotesGuides.lua` reads discrete guide coordinates; `CompassHandyNotesGuideSource.lua` retains the selected parent's guide snapshot. `CompassHandyNotesTooltip.lua` owns native hover content on the private tooltip and cancels deferred work on retirement.

## Gotchas
- Complete provider snapshots have no polling deadline. Named updates invalidate only that provider; incomplete startup, pending names and failures retry after 30 seconds while retaining completed providers. Failures mark discovery pending so previously published markers cannot imply completion/removal. The discovery owner retains clean, completed snapshots on ordinary subzone movement within the same map/artwork; indoor/new-area events, pending/active work, core settings, profiles and map/phase/world changes still reconcile.
- Iterators share mutable map state and must finish synchronously before discovery yields. Copy records before releasing iterator state; cancelled work cannot repopulate a replacement cache. Unchanged snapshots do not rebuild markers.
- Discovery never renders tooltips. Native hover calls returned Zarillion nodes' Render/Unrender, avoiding OnEnter's world-map focus/refresh and global GameTooltip ownership.
- MapNotes text uses zone-iterator metadata and its locale NPC cache, verified against 3.6.4. Continent iterators lack that metadata. Unknown providers retain the provider/coordinate fallback; this is not a general HandyNotes text API.
- Kemayo registers names without `HandyNotes_`. Only yielded points are read; native filters retain ownership. Text callbacks/reward names run inside the protected snapshot, never in rendering. Missing native names deduplicate within a scan and retry; successful names cache for the session. Fully resolved formatted strings use a 512-entry FIFO session cache; callbacks still execute before lookup, changed input gets a new result, and pending text never enters it. Plain text bypasses parsing. Unknown tokens retain their supplied fallback or identifier. Kemayo hover/click callbacks own global tooltip/map state and are not invoked; Compass uses the copied label/note.
- `Compass.HandyNotes.<provider>` totals include nested `.GetNodes2` (native setup/refresh) and `.Nodes` (iterator/filtering plus copied metadata) spans, closed even on failure. Read the parent's total to compare whole scans. `HandyNotes/` counters distinguish hook invalidations, provider-cache decisions, retries/failures and cumulative copied records; `TextCacheHit` and `TextRendered` count reused/reparsed formatted strings. Cached/idle reads do not enter a scan span; there are no per-node spans. Standalone needs a supplied profiler. Independent native map/minimap/background work remains outside these spans.
- Zarillion support uses twelve verified provider names, not a name prefix. Each pack supplies its own artwork and does not require Midnight. Only discrete POI/entrance coordinates become destinations; paths, area outlines and focus glows do not.
- Provider/node identity and original coordinates survive selection and menus. Stale actions cannot redirect tracking. Following a guide keeps its group and instructions without repeating the parent's native click.
- Guide keys include the provider. Native provider updates refresh the selected snapshot; unrelated selection, cleared waypoint, removed parent or lifecycle/context reset retires it. Independent map hover/focus does not own Compass guidance.
- Provider art retains crop, tint and alpha, but map scale multipliers cannot enlarge compass icons. Instruction markup uses the originating pack's circle texture rather than unsupported font glyphs.

## Secrets
External tables, iterators, coordinates and actions pass secret-first boundary validation before access. Native provider calls are guarded trust boundaries; completed records contain only validated destinations.

## References
`../README.md`, `../../Discovery/README.md`, `../../Navigation/README.md`; [HandyNotes API](https://github.com/Nevcairiel/HandyNotes/blob/7b9f700fb5653351cde99d4c17d46a5bc01278c9/HandyNotes.lua), [Zarillion shared core](https://github.com/zarillion/handynotes-plugins/tree/master/core), [Kemayo shared handler](https://github.com/kemayo/wow-handynotes-handler). Workspace `develop/handynotes-kemayo/` records source provenance, Lua 5.1 checks and native verification limits.
