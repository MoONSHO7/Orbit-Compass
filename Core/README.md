# Compass runtime

## Description
The Compass product controller, native navigation sources, rendering and interaction.

## Purpose
Own navigation behavior independently of the optional Orbit host and shared UI implementation.

## Implementation
`CompassCompatibility.lua` selects a compatible host before localization and defaults load. `Foundation/CompassConstants.lua` and `Plugin/CompassDefaults.lua` define geometry and per-surface defaults. Services select shared UI and native defaults; the optional `Integrations/` bridge creates Orbit's actual plugin. `Plugin/Compass.lua` creates its native event/update frame and callback during addon load; its private callback boundary retains optional Orbit profiler spans without using the host update driver. The controller owns cached settings and frame lifecycle. Appearance changes reuse discovery caches; category changes invalidate only their source, while Orbit profile switches refresh saved locations and release old TomTom markers. Standalone visibility settings apply only when pet/vehicle hiding changes; Edit Mode transitions redraw without restarting discovery.

Collectors feed independent discovery caches. Complete map POIs remain cached until native POI/quest-hub updates or a context reset; timed points schedule expiry checks and incomplete data schedules retries. Quest events refresh the watched-quest catalog; route updates refresh only the supertracked quest through the budgeted queue, retaining other markers and the full-scan deadline. Sources project destinations, targets resolve guidance, and position/bearings/projection prepare the ribbon. Marker/view modules own pooled art and input: POIs stay at 1.2x within 30% of the configured range, then scale linearly through 1.0x at 50%, 0.75x at 75%, and 0.5x at or beyond its limit. Spacing and click areas reserve the 1.2x footprint. Navigation owns the detached arrow; navigation settings own units and visibility independently of Canvas. Commands, nearby selection and saved locations preserve native waypoint behavior.

## Gotchas
- Every frame, event handler, cache and coroutine belongs to this addon controller. Do not create a synthetic Orbit global or copy its engine namespace.
- An incompatible or duplicate host leaves declarations dormant: boot destroys the private context and reports the conflict before settings initialization. File-load command and global exports must honor that gate.
- Navigation uses two settings indices; index 2 owns arrow position, size, text and Canvas drafts. Arrow reset clears the saved position after shared movement guards accept the current screen-relative default, so later display/scale changes stay dynamic. The ribbon height is fixed at 20, including resize bounds; legacy Height settings are ignored. Direction and detail rows extend below that frame, reserving space for the largest POI and selection badge. Font, layout and icon-size changes invalidate cached heading geometry and spacing.
- Source validity guards precede arithmetic, field access and comparisons. Runtime caches reset on world/map/player-phase changes. Same-map zone updates replace each source snapshot when its scan completes; empty lists are valid snapshots and missing records retain a retry.
- Missing map-position samples retain the previous calibration only on the same map and world instance; validated world movement still updates the position. Initial acquisition and changed instances require fresh map coordinates.
- `SUPER_TRACKING_PATH_UPDATED` can repeat while navigating. It must not rescan every watched quest or rebuild unchanged marker lists; `Compass.Discovery.QuestPath` measures targeted work separately from full quest-scan slices.
- Disabling or entering an instance cancels scans and hides both roots without clearing the player's native waypoint.

## Secrets
Map records, external waypoints, facing and coordinates pass secret-first validity gates before Lua operations. Calibration stores only validated map/world coordinates.

## References
`../README.md`, the workspace `wow-secrets`, `pixel`, `orbit-settings`, `orbit-tooltips` and `strata-strategy` skills.
