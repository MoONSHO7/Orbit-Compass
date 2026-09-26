# Compass controller

## Description
Controller construction, product defaults and runtime lifecycle.

## Purpose
Give standalone and hosted Compass one owner for frames, events, caches and settings application.

## Implementation
`Plugin.xml` loads defaults and standalone services, then the optional `../Integrations/Orbit/Orbit.lua` bridge before constructing the controller. `CompassController.lua` selects the standalone store/controller or the real Orbit plugin. `Compass.lua` declares lifecycle methods and creates the native event/update owner during file load; `../CompassBoot.lua` starts the application only after every feature bundle has loaded.

`CompassServices.lua` supplies the product's UI context and rendering/positioning hooks, including standalone Orbit UI and Orbit UI Chat paths. The Orbit bridge replaces supported hooks and private font paths before feature modules capture them. `CompassDefaults.lua` owns both surfaces' defaults; settings continue through the selected controller and store.

## Gotchas
- Never invoke lifecycle methods to force a refresh. The selected application/host owns activation and settings application.
- Compass is always active in standalone and host modes: the WoW addon list owns availability, while Orbit owns hosted runtime activation and profile application. Stale standalone `Enabled` and hosted `DisabledPlugins.Compass` values cannot suppress startup.
- Unsupported clients never start the application. Forever may use the standalone controller or a compatible Orbit host, while its feature policy still withholds unaudited activities. Optional pet-battle calls are guarded; Discovery registers supported source events. Disable disconnects provider sessions before retiring Search jobs, listeners and demand.
- Appearance changes reuse discovery caches. Category changes invalidate only their source; profile switches also refresh saved locations.
- Standalone visibility applies when pet/vehicle hiding changes. Edit Mode transitions redraw without restarting discovery. Disabling or entering an instance stops scans and hides both surfaces without clearing the player's native waypoint.
- The event/update owner exists before hosted activation, but frame construction waits for the lifecycle. All methods must be declared before boot starts that lifecycle.

## References
`../README.md`, `../Integrations/Orbit/README.md`; Orbit `Core/Plugin/README.md` and the `orbit-settings` skill.
