# Compass navigation

## Description
Waypoint selection, player positioning and the detached navigation arrow.

## Purpose
Own destinations and guidance independently of how the ribbon chooses visible icons.

## Implementation
`Navigation.xml` loads waypoint commands and target selection, saved locations and choice menus, player position/bearings, then arrow construction, rendering and component settings. `CompassWaypoint.lua` owns explicit native waypoint changes; commands and `CompassPointMenu.lua` feed that same selection path. `CompassLocations.lua` owns saved destinations, and `CompassTargets.lua` chooses guidance. The order is corpse, native route step, selected destination, then gossip directions. `CompassTrackedPin.lua` identifies the super-tracked map pin and decides whether Compass follows it (Follow Targets, or a pin chosen through Search). It also resolves the pin's destination from the search choice, the open world map, or the landmark index in `../Search/`.

`CompassWaypoint.lua` also tracks search landmarks. Pin types use native super-tracking; quests are watched and super-tracked; zones, other kinds and failed pins use a labelled waypoint. The same file adopts newly placed user waypoints: world-map placement leaves a pin untracked, so the next marker rebuild tracks it once to obtain native routing.

`CompassAutoAdvance.lua` advances an explicitly selected Compass point to the nearest enabled point after source removal or optional arrival within 15 yards. Arrow settings cache the mode and same-type filter; the existing update owner checks settled discovery at a bounded cadence. Visited identities belong to the current selection sequence and reset with settings or discovery context.

`CompassPosition.lua` calibrates validated map/world coordinates; `CompassBearings.lua` derives heading and distance. `CompassNavigation.lua` owns the root and placement, `CompassNavigationView.lua` draws it, and `CompassNavigationSettings.lua` resolves component preferences and units. The optional Orbit Canvas adapter stays in `../Integrations/Orbit/`.

Navigation selection reads the current map position once only when an eligible, non-dismissed candidate needs ranking. Bearing cadence is unchanged: position and selected targets update per frame, full refreshes settle movement, and ordering keeps its existing interval. During profiling, `Compass.Bearings.Position` and `Compass.Bearings.Update` split position sampling/calibration from bearing maintenance inside the existing aggregate. Fixed counters identify unchanged, full, incremental and unavailable updates, ordering decisions, position fallback/sync and navigation lookup use.

## Gotchas
- Destination version 1 uses IDs `<clientFamily>:<lowercase name>` and stores family, map, coordinates and readable `worldInstance`. Collection handles keep their standalone/profile ownership. Reads require the current family, map and recorded world instance. Foreign, legacy and unknown-version records remain stored but dormant; no migration guesses origin. Re-save a confirmed place to create a qualified record. `/oway list` identifies dormant records; `/oway forget retail:name` deletes one explicitly. The 100-record limit includes dormant records.
- Indexed Search actions require current catalog membership, live marker actions require current identity, and saved actions reread the collection. Disabled/suppressed clients reject waypoint changes. Native content/vignette tracking and explicit quests obey client policy.
- Index 2 owns arrow position, size, text and Canvas drafts. Reset clears the saved position only after movement guards accept the current default, so later scale/display changes remain dynamic.
- Map-position gaps retain calibration only on the same map and world instance. Initial acquisition and changed instances require fresh coordinates.
- Position and bearing phases do not catch errors; the existing update callback owns error handling. Failed phase spans remain visible to the profiler's discarded/unclosed-span checks.
- Menu choices capture labels, destinations and provider actions; regrouping cannot retarget a choice. Native HandyNotes actions run only on explicit selection, and following a guide retains its parent instructions.
- Route steps are guidance, not destinations. Clicks, menus, the target hotkey and auto-advance skip them. A step within arrival
  range of the selected destination yields to it, and dismissing a routed pin hides the whole trip until the native selection changes.
  Saving a routed target stores its resolved destination, and is refused when the pin's destination is unknown.
- Waypoint adoption compares against the last observed pin, so login, reloads and zone changes never re-track an existing pin, and
  untracking a pin on the world map is respected. Quest-offer and housing pins cannot be resolved off-map and rely on route steps.
- Auto-advance only owns Compass-selected waypoints with a source identity. Removal requires a ready observation from that source; pending, failed and disabled sources cannot confirm disappearance. Next targets come only from ready sources, and ownership follows the new target. Arrival remains separate. It pauses for other native tracking, ignores ribbon facing and clears its waypoint when no eligible unvisited point remains. Automatic choices never invoke provider clicks. Source disappearance is not proof of harvesting; ordinary minimap gathering dots expose no positions.
- Description text uses small white PT Sans Narrow with a gap below the name. Provider markup survives independently of name styling; name alignment and visibility still govern the description.
- The arrow inherits its immutable click-through template from Foundation. Do not reintroduce protected mouse-routing setters during construction.
- Slash compatibility aliases are claimed only when free. Disabling Compass retires its handlers without taking another addon's aliases or clearing the native waypoint.

## Secrets
Destination and map/world samples pass source validation before arithmetic. Position calibration stores only validated coordinates.

## References
`../README.md`, `../Discovery/README.md`, `../Ribbon/README.md`, `../Integrations/HandyNotes/README.md`; the `pixel`, `wow-secrets` and `orbit-settings` skills.
