# Compass foundation

## Description
Immutable client policy, artwork boundaries, constants, geometry helpers and native button declarations.

## Purpose
Provide the dependency floor for Compass without controller state, settings reads or addon integration behavior.

## Implementation
`CompassClientFeatures.lua` loads directly from the TOC after libraries, before compatibility/localization. It consumes `UI.Client` and owns product source, point and kind eligibility plus minimum native contracts. `Foundation.xml` loads `CompassConstants.lua`, `CompassArtwork.lua`, `CompassMath.lua` and `CompassText.lua`, then includes `CompassTemplates.xml` before runtime construction. Consumers use those private Addon exports; constants own shared point labels and pin prefixes. `Addon.Artwork` validates native atlases and rejected texture assignments, falling back to a native marker or the bundled arrow.

## Gotchas
- Keep this module independent of the controller, services and optional host. Defaults belong to `../Plugin/`, not Foundation.
- Feature policy is constant for the session and never rewrites preferences. Optional enum keys are inserted only when present. Enabling another Forever activity requires a policy/evidence change.
- Atlas existence is cached per session; lookup availability does not prove correct artwork or asynchronous residency. Preserve existing assets unless Forever testing produces a nil error tied to that asset; names such as Housing do not establish client availability.
- `Text.Fold` changes case and separators only through explicit byte ranges. Locale-aware `string.lower` and `%s`/`%p` can
  rewrite UTF-8 lead or continuation bytes, which corrupts accented and Cyrillic names.
- Fixed click-through behavior belongs in the templates. `SetPassThroughButtons` is protected even on Compass's insecure buttons; marker pools can grow during combat.

## References
`../README.md`, `../Plugin/README.md`, `../Ribbon/README.md`; Blizzard `Blizzard_SharedXML/UI.xsd` and `Blizzard_APIDocumentationGenerated/SimpleScriptRegionAPIDocumentation.lua`.
