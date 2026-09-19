# Compass settings UI

## Description
Appearance schemas and the Points table shared by standalone and hosted settings.

## Purpose
Keep settings presentation separate from navigation, discovery and controller lifecycle.

## Implementation
`Config.xml` registers the hotkey and Points widgets before loading `CompassSettings.lua`, which supplies `Addon.SettingsTabs`. `CompassPointHotkey.lua` owns native binding capture. `CompassPointsSettings.lua` owns the pooled visibility matrix and column explanations; it reads and writes preferences through `../Discovery/CompassPointVisibility.lua`.

The standalone application and Orbit bridge both consume these schemas and widget registrations. Arrow schemas use the component preferences and distance formatting owned by `../Navigation/`.

Arrow appearance and Behaviour use separate tabs. Behaviour owns four explained checkboxes: auto-advance, same-type routing, corpse recovery and native map tracking. Auto-advance presents the existing mode setting as on/off; enabled modes use arrival-or-removal semantics. Same-type routing is visible only while auto-advance is enabled; toggling refreshes the active tab without changing the saved same-type preference.

## Gotchas
- Both settings windows must use the same widget renderer and controller accessors. Standalone changes trigger application through its store callback; hosted changes explicitly request application.
- Points intersects all 18 definitions with the same client policy as Discovery/Search. GatherMate2 and HandyNotes also require their addon to be loaded. Hidden rows retain saved preferences and occupy no space; Forever Points reset preserves unsupported Retail rows. Filtering never persists false merely because the client lacks a feature.
- Keybindings belong to the current WoW binding set, not the Compass profile. Capture stops on hide or combat entry, and failed assignment preserves the previous keys.
- Controls, rows and header hover regions are reused with their table. Hover uses the private layout tooltip; release must retire any visible tooltip and cell callbacks.
- The hotkey's temporary visibility mode is owned by Discovery. It must not add keyboard polling or settings reads to the render loop.

## References
`../README.md`, `../Discovery/README.md`, `../Navigation/README.md`, `../../Localization/README.md`; the `orbit-settings`, `orbit-tooltips` and `pixel` skills.
