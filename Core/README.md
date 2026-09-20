# Compass Core

## Description
Compass runtime modules, composed into one standalone or Orbit-hosted controller.

## Purpose
Keep startup, settings, discovery, navigation, ribbon rendering and external integrations easy to locate and change independently.

## Implementation
`Foundation/CompassClientFeatures.lua` consumes `LibOrbitUI.Client` before compatibility/localization. Its immutable policy is shared by settings, collectors, Search and navigation; Discovery owns data readiness. `CompassCompatibility.lua` selects a compatible optional Orbit host on Retail or Forever. `Core.xml` loads the bundles below, ending with `CompassBoot.lua`, which constructs the application after all declarations exist.

| Module | Owns |
|---|---|
| [Foundation](Foundation/README.md) | Immutable constants, geometry helpers and native button templates |
| [Plugin](Plugin/README.md) | Defaults, service selection, controller construction, events and runtime lifecycle |
| [Discovery](Discovery/README.md) | Validated point records, area/alternate visibility, source snapshots and refresh scheduling |
| [Native sources](Discovery/Sources/README.md) | Blizzard map, quest, travel and tracked-content collectors |
| [Navigation](Navigation/README.md) | Destinations, commands, saved locations, player positioning and the detached arrow |
| [Ribbon](Ribbon/README.md) | Visible-point selection, overlap groups, pooled icons, headings and the Alt callout |
| [Search](Search/README.md) | World landmark index, category/place ranking and the inline search field |
| [Config](Config/README.md) | Appearance schemas, Points matrix and native hotkey capture |
| [Integrations](Integrations/README.md) | Optional-addon lifecycle, HandyNotes and the Orbit host bridge |

Bundle order is Foundation → Plugin → Discovery → Navigation → Integrations → Ribbon → Search → Config → boot. Discovery supplies records to Navigation and Ribbon; Config updates the selected controller's preferences, and external adapters feed the existing source caches. Each directory's XML defines its local load order.

## Gotchas
- All modules compose the same controller. LibOrbitUI supplies common UI/runtime infrastructure; an available Orbit host supplies its profile, theme, fade, layering and Canvas services.
- The Orbit bridge loads inside `Plugin/Plugin.xml` after standalone services and before controller construction. `Integrations/Integrations.xml` loads its Canvas adapter later, once navigation exists. Preserve this split when adding dependencies.
- Feature files declare methods during loading; boot starts the lifecycle after every bundle has finished. Compatibility failures leave those declarations dormant and preserve an existing host's controller, commands and bindings.
- Keep native collectors under Discovery and addon-specific contracts with their integration. Provider caches, click identity and guide ownership must not migrate into the ribbon render loop.

## Secrets
Discovery owns secret-first point validation; Navigation retains validated map/world samples, and Ribbon consumes those results. See the owning module README before changing a native-data boundary.

## References
`../README.md`, `../Localization/README.md`; Orbit `Core/README.md` and the workspace architecture/skill standards.
