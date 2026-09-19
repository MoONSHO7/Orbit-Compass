# Compass ribbon

## Description
Visible-point selection, overlapping marker presentation and compass artwork.

## Purpose
Render existing navigation data with stable icon identity and bounded work per frame.

## Implementation
`Ribbon.xml` loads marker grouping and pooled views, projection/selection, the Alt callout and root rendering. `CompassProjection.lua` chooses visible points from discovery records. `CompassMarkerGroups.lua` rebuilds exact pixel overlaps while retaining validated distance order; `CompassMarkerView.lua` binds stable pooled buttons and consumes the same snapped left edge. `CompassView.lua` combines markers, headings and artwork, while `CompassPeek.lua` draws one connected name/distance callout. Optional profiler phases separate grouping from marker binding/rendering; fixed counters record depth sorts, skipped sorts and membership changes.

## Gotchas
- Native atlases and rejected provider textures use `Addon.Artwork` fallbacks. Failed textures do not inherit provider crop coordinates; quest symbol layers require both atlases. Selection glow retains `housing-basic-panel-gradient-header-bg`, confirmed by the user on Retail and Forever. Other native appearance and residency still need both clients.
- The 24-marker budget retains navigation/category priority. Distance with stable key ties orders icons within levels 1–24 of the ribbon's 32-level footprint; non-interactive selection badges use level 25, the Alt callout 26 and Search's inline field 27.
- Overlap preserves positions. Nearer art covers farther art, exposed portions remain clickable, and grouped clicks open Navigation's choice menu with every member. Membership validation uses marker identity; distance/key order is checked on every render, while snapped overlap intervals always rebuild so turning and fractional-pixel edges cannot retain stale groups.
- GatherMate2 markers sit below the line with a two-pixel gap. Their overlap groups stay separate from the upper row, including when selected for navigation.
- POI size uses fixed yard distances, independent of visibility range: 1.4x through 150 yards, linearly shrinking to 0.45x at 1,000 yards and staying there beyond. HandyNotes uses the same curve and icon size.
- The ribbon is fixed at 20 logical units high; legacy Height is ignored. Directions and detail rows extend below it, reserving room for the largest icon and selection badge. Style changes invalidate cached heading geometry and spacing.
- Alt labels only the nearest rendered, untracked destination, skipping invisible and fully covered points. Modifier events request redraw only; release, Edit Mode and root hiding retire the callout. No discovery, native actions or tooltip work belongs in this preview.
- New pooled buttons inherit Foundation's click-through template. Pool growth may occur during combat, so creation must not call `SetPassThroughButtons`.

## Secrets
The ribbon consumes validated coordinates and distances from Discovery/Navigation; it does not inspect raw native point records.

## References
`../README.md`, `../Foundation/README.md`, `../Discovery/README.md`, `../Navigation/README.md`; the `pixel`, `strata-strategy`, `orbit-tooltips` and `taint-debug` skills.
