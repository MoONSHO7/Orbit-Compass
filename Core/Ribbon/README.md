# Compass ribbon

## Description
Visible-point selection, overlapping marker presentation and compass artwork.

## Purpose
Render existing navigation data with stable icon identity and bounded work per frame.

## Implementation
`Ribbon.xml` loads the [marker bundle](Markers/README.md), projection and selection, the Alt callout, the place title
and root rendering. `CompassProjection.lua` chooses visible points from discovery records. The marker bundle groups
exact pixel overlaps and renders stable pooled buttons using the same snapped left edge. `CompassView.lua` combines
markers, headings and artwork after Discovery's city-fold blend adjusts the selection; `CompassPeek.lua` draws one
connected name and distance callout, and `CompassPlaceLabel.lua` names the place the view centre falls on
(`FindCompassFacedPlace`). A fold or title fade in progress keeps rendering (`compassCityFoldAnimating`,
`compassPlaceLabelAnimating`). Optional profiler phases separate grouping from marker binding and rendering. Fixed
counters record depth sorts, skipped sorts and membership changes.

## Gotchas
- Native atlases and rejected provider textures use `Addon.Artwork` fallbacks. Failed textures do not inherit provider
  crop coordinates; quest symbol layers require both atlases. Selection glow retains
  `housing-basic-panel-gradient-header-bg`, confirmed by the user on Retail and Forever. Other native appearance and
  residency still need both clients.
- The `MAX_MARKERS` budget of 24 retains navigation/category priority. Distance with stable key ties orders icons within
  levels 1–24 of the ribbon's 32-level `STRATA_FOOTPRINT`; non-interactive selection badges use level 25, the Alt
  callout 26 and Search's inline field 27.
- Overlap preserves positions. Nearer art covers farther art, exposed portions remain clickable, and grouped clicks open
  Navigation's choice menu with every actionable member (`group.actions`). Membership validation uses marker identity;
  distance/key order is checked on every render, while snapped overlap intervals always rebuild so turning and
  fractional-pixel edges cannot retain stale groups.
- GatherMate2 and live Forever resource markers sit below the line with a two-pixel gap. Their overlap groups stay
  separate from the upper row. Live observations are display-only, with circular masks and a thin gold ring reused by each
  pooled slot; other marker kinds remove the masks and hide the ring. Its native ring/icon ratio determines the ring's
  bounds, included in overlap/gap geometry. While Discovery's `displayMarkers` holds a resource row, headings reserve
  its maximum near footprint, recomputed only when that list is replaced; GatherMate's unringed band is reserved while
  its row shows and GatherMate is connected. Display-only markers never click, count toward overlap choices or
  advertise a click-to-track action.
- Points fade out over the last stretch of their range (`MARKER_RANGE_FADE_*`). Tracked destinations and a town's own
  points never range-fade, and a place icon raised by a folded member fades only as that member does. A marker reaching zero alpha is hidden,
  never left as a transparent button that still takes hovers and clicks. A fold's fading side is not interactive and
  joins no overlap choice, Alt callout, Show Label line or target hotkey.
- POI size follows each point type's own visibility range, its Points row range or Marker Range (up to 5,000 yards):
  1.4x through 150 yards, shrinking linearly to 0.45x at the range edge (`MARKER_NEAR_*`/`MARKER_FAR_SCALE` in
  Foundation). HandyNotes uses the same curve and icon size; place icons travel it at half the rate
  (`CITY_DISTANCE_SHRINK`), so at their range edge they are halfway and reach 0.45x only when a folded member raises
  them from twice that distance.
- The place title only names city and town icons, while the view centre is within the place's own angular half-width
  (3–15°), in Blizzard's `GameFontNormalLarge` unless the Font setting overrides its face (enemy places red), over a
  desaturated, darkened `BonusChest-OrangeSmoke-Wide` band that fades with it. Place Names (Off, Above, Below) chooses
  its side, with the distance underneath in Blizzard's small text: above, the distance line sits 20 px over the largest
  place icon; below, the name starts 16 px under Show Label's line, holding that line from the first frame a place is
  faced and yielding to Alt's callout. While the place offers quests (Discovery's `offersQuests`), Blizzard's
  `QuestNormal` bang hangs left of the name, which stays centred, and fades with it. At a screen edge the title moves
  toward the ribbon to stay visible. Each 0.2-second fade starts from the frame that triggers it. A font object resets
  colour and justification, so restyling restores both (an enemy title stays red).
- The ribbon is fixed at `RIBBON_HEIGHT` (20 logical units); legacy Height is ignored. Directions and detail rows extend
  below it, reserving room for the largest icon and selection badge. Style changes invalidate cached heading geometry
  and spacing.
- Alt labels only the nearest rendered, untracked destination, skipping points hidden beneath one tracked icon in their
  own row; the callout box rounds up to whole pixels so its text never wraps early, and claims Show Label's line only
  while it draws. Modifier events request redraw only; release, Edit Mode and root hiding retire the callout. No
  discovery, native actions or tooltip work belongs in this preview.
- New pooled buttons inherit Foundation's click-through template. Pool growth may occur during combat, so creation must
  not call `SetPassThroughButtons`.

## Secrets
The ribbon consumes validated coordinates and distances from Discovery/Navigation; it does not inspect raw native point
records.

## References
`../README.md`, `../Foundation/README.md`, `../Discovery/README.md`, `../Navigation/README.md`; the `pixel`,
`strata-strategy`, `orbit-tooltips` and `taint-debug` skills.
