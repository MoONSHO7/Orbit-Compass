# Compass foundation

## Description
Immutable constants, pure geometry helpers and native button declarations.

## Purpose
Provide the dependency floor for Compass without controller state, settings reads or addon integration behavior.

## Implementation
`Foundation.xml` loads `CompassConstants.lua`, then `CompassMath.lua`, and includes `CompassTemplates.xml` before any runtime frame construction. Consumers use `Addon.Constants` and `Addon.Math`; button factories inherit the declared marker and arrow templates.

## Gotchas
- Keep this module independent of the controller, services and optional host. Defaults belong to `../Plugin/`, not Foundation.
- Fixed click-through behavior belongs in the templates. `SetPassThroughButtons` is protected even on Compass's insecure buttons; marker pools can grow during combat.

## References
`../README.md`, `../Plugin/README.md`, `../Ribbon/README.md`; Blizzard `Blizzard_SharedXML/UI.xsd` and `Blizzard_APIDocumentationGenerated/SimpleScriptRegionAPIDocumentation.lua`.
