# Compass localization

## Description
A standalone nine-locale string registry for Compass and its settings.

## Purpose
Keep commands, point tooltips and controls localized without reading Orbit SavedVariables.

## Implementation
`Generated.lua` snapshots the Compass/common keys from Orbit's authored localization domains, including dynamic point-type labels. `Compass.lua` overlays existing keys from the compatible `addon.OrbitHost.L`, then applies product-owned availability messages and presentation labels in the host's active locale or the game locale. These overrides shorten the arrow label and supply the separate Compass: Arrow settings title. Product modules consume the private `addon.L` table. Locale aliases map enGB to enUS and esMX to esES.

## Gotchas
Preserve all nine locales when adding or changing strings. Keep the generated snapshot intact; product-specific wording belongs in `Compass.lua` overrides. Orbit language changes take effect after the requested UI reload; this module does not subscribe to live locale changes. An incompatible Orbit host gets a localized update/disable warning and must not replace the existing keybinding category label.

## References
Orbit `Localization/README.md`, `../Core/README.md`.
