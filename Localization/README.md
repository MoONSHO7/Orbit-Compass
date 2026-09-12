# Compass localization

## Description
A standalone nine-locale string registry for Compass and its settings.

## Purpose
Keep commands, point tooltips and controls localized without reading Orbit SavedVariables.

## Implementation
`Localization.xml` loads the generated registry before the product overlay. `Generated.lua` snapshots the Compass/common keys from Orbit's authored localization domains, including dynamic point-type labels. `Compass.lua` overlays existing keys from the compatible `addon.OrbitHost.L`, then supplies product-owned availability messages, navigation labels, point controls and HandyNotes fallback labels in the host's active locale or the game locale. Product modules consume the private `addon.L` table. Locale aliases map enGB to enUS and esMX to esES.

## Gotchas
Preserve all nine locales when adding or changing strings. Keep the generated snapshot intact; product-specific wording belongs in `Compass.lua` overrides. Orbit language changes take effect after the requested UI reload; this module does not subscribe to live locale changes. An incompatible Orbit host gets a localized update/disable warning and must not replace the existing keybinding category label.

## References
Orbit `Localization/README.md`, `../Core/README.md`.
