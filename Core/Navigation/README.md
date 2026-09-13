# Compass navigation

## Description
Waypoint selection, player positioning and the detached navigation arrow.

## Purpose
Own destinations and guidance independently of how the ribbon chooses visible icons.

## Implementation
`Navigation.xml` loads waypoint commands and target selection, saved locations and choice menus, player position/bearings, then arrow construction, rendering and component settings. `CompassWaypoint.lua` owns explicit native waypoint changes; commands and `CompassPointMenu.lua` feed that same selection path. `CompassLocations.lua` owns saved destinations, and `CompassTargets.lua` chooses guidance including corpse targets.

`CompassAutoAdvance.lua` advances an explicitly selected Compass point to the nearest enabled point after source removal or optional arrival within 15 yards. Arrow settings cache the mode and same-type filter; the existing update owner checks settled discovery at a bounded cadence. Visited identities belong to the current selection sequence and reset with settings or discovery context.

`CompassPosition.lua` calibrates validated map/world coordinates; `CompassBearings.lua` derives heading and distance. `CompassNavigation.lua` owns the root and placement, `CompassNavigationView.lua` draws it, and `CompassNavigationSettings.lua` resolves component preferences and units. The optional Orbit Canvas adapter stays in `../Integrations/Orbit/`.

Navigation selection reads the current map position once only when an eligible, non-dismissed candidate needs ranking. Bearing cadence is unchanged: position and selected targets update per frame, full refreshes settle movement, and ordering keeps its existing interval. During profiling, `Compass.Bearings.Position` and `Compass.Bearings.Update` split position sampling/calibration from bearing maintenance inside the existing aggregate. Fixed counters identify unchanged, full, incremental and unavailable updates, ordering decisions, position fallback/sync and navigation lookup use.

## Gotchas
- Index 2 owns arrow position, size, text and Canvas drafts. Reset clears the saved position only after movement guards accept the current default, so later scale/display changes remain dynamic.
- Map-position gaps retain calibration only on the same map and world instance. Initial acquisition and changed instances require fresh coordinates.
- Position and bearing phases do not catch errors; the existing update callback owns error handling. Failed phase spans remain visible to the profiler's discarded/unclosed-span checks.
- Menu choices capture labels, destinations and provider actions; regrouping cannot retarget a choice. Native HandyNotes actions run only on explicit selection, and following a guide retains its parent instructions.
- Auto-advance only owns Compass-selected waypoints with a source identity. It pauses for other native tracking, ignores ribbon facing, and clears its waypoint when no eligible unvisited point remains. Automatic choices never invoke provider click actions. Source disappearance is not proof of harvesting; ordinary minimap gathering dots have no exposed position enumeration.
- Description text uses small white PT Sans Narrow with a gap below the name. Provider markup survives independently of name styling; name alignment and visibility still govern the description.
- The arrow inherits its immutable click-through template from Foundation. Do not reintroduce protected mouse-routing setters during construction.
- Slash compatibility aliases are claimed only when free. Disabling Compass retires its handlers without taking another addon's aliases or clearing the native waypoint.

## Secrets
Destination and map/world samples pass source validation before arithmetic. Position calibration stores only validated coordinates.

## References
`../README.md`, `../Discovery/README.md`, `../Ribbon/README.md`, `../Integrations/HandyNotes/README.md`; the `pixel`, `wow-secrets` and `orbit-settings` skills.
