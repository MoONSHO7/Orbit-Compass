# Compass markers

## Description
Pooled ribbon markers, overlap groups, artwork and input.

## Purpose
Render one bounded set of marker buttons while keeping each button's current destination and tooltip in sync.

## Implementation
`Markers.xml` loads overlap groups, input and artwork before the pool and view. `CompassMarkerGroups.lua` assigns
pixel intervals and group actions. `CompassMarkerInput.lua` owns mouse scripts, tooltip binding and destination
validation. `CompassMarkerArt.lua` owns atlas and texture binding, including resource masks. `CompassMarkerPool.lua`
owns button construction, reset and reuse by key. `CompassMarkerView.lua` positions and fades each bound button.

## Gotchas
- A click must match the destination captured on press, even if a new record reuses the slot and its artwork.
  Rebinding a hovered marker refreshes its tooltip. Hiding and releasing the slot retire both hover and press state.
- The pool uses the Foundation template for click passthrough. Its masks and resource rings stay allocated for reuse.
- Verify native hover, left-click tracking, right-click passthrough and mixed marker artwork on both clients.

## References
`../README.md`, `../../Foundation/CompassTemplates.xml`, `check-resources.py`.
