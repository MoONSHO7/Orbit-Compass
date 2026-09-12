# HandyNotes integration

## Description
HandyNotes provider snapshots, note text, native tooltips and selected guide points.

## Purpose
Expose map notes as compass destinations while preserving provider identity and avoiding repeated scans of static data.

## Implementation
`HandyNotes.xml` declares the verified Zarillion family, text/guide readers and click adapter before the collector and tooltip adapter. `CompassHandyNotes.lua` caches enabled `GetNodes2` providers for the current map context. `CompassHandyNotesZarillion.lua` owns exact provider identities and artwork; `CompassHandyNotesText.lua` resolves labels and numbered instructions.

`CompassHandyNotesClick.lua` captures and invokes explicit native left-click actions. `CompassHandyNotesGuides.lua` reads discrete guide coordinates; `CompassHandyNotesGuideSource.lua` retains the selected parent's guide snapshot. `CompassHandyNotesTooltip.lua` owns native hover content on the private tooltip and cancels deferred work on retirement.

## Gotchas
- Complete provider snapshots have no polling deadline. Named updates invalidate only that provider; incomplete startup, pending names and failures retry after 30 seconds while retaining completed providers. Core settings, profiles and context changes reconcile the full cache.
- Iterators share mutable map state and must finish synchronously before discovery yields. Copy records before releasing iterator state; cancelled work cannot repopulate a replacement cache. Unchanged snapshots do not rebuild markers.
- Discovery never renders tooltips. Native hover calls returned Zarillion nodes' Render/Unrender, avoiding OnEnter's world-map focus/refresh and global GameTooltip ownership.
- MapNotes text uses zone-iterator metadata and its locale NPC cache, verified against 3.6.4. Continent iterators lack that metadata. Unknown providers retain the provider/coordinate fallback; this is not a general HandyNotes text API.
- Zarillion support uses twelve verified provider names, not a name prefix. Each pack supplies its own artwork and does not require Midnight. Only discrete POI/entrance coordinates become destinations; paths, area outlines and focus glows do not.
- Provider/node identity and original coordinates survive selection and menus. Stale actions cannot redirect tracking. Following a guide keeps its group and instructions without repeating the parent's native click.
- Guide keys include the provider. Native provider updates refresh the selected snapshot; unrelated selection, cleared waypoint, removed parent or lifecycle/context reset retires it. Independent map hover/focus does not own Compass guidance.
- Provider art retains crop, tint and alpha, but map scale multipliers cannot enlarge compass icons. Instruction markup uses the originating pack's circle texture rather than unsupported font glyphs.

## Secrets
External tables, iterators, coordinates and actions pass secret-first boundary validation before access. Native provider calls are guarded trust boundaries; completed records contain only validated destinations.

## References
`../README.md`, `../../Discovery/README.md`, `../../Navigation/README.md`; [HandyNotes API](https://github.com/Nevcairiel/HandyNotes/blob/7b9f700fb5653351cde99d4c17d46a5bc01278c9/HandyNotes.lua), [Zarillion shared core](https://github.com/zarillion/handynotes-plugins/tree/master/core).
