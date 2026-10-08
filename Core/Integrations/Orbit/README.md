# Orbit host integration

## Description
Optional plugin registration and advanced rendering/Canvas capabilities from a compatible Orbit host.

## Purpose
Preserve Orbit profile ownership and customization while standalone Compass retains its own controller and store.

## Implementation
`../../CompassCompatibility.lua` selects the host before localization: it accepts Orbit only when
`Orbit.ExternalUIHost.legacyPluginVersion == 1`, `Orbit.GetPlugin` exists and no `Compass` plugin is already registered,
exporting `Addon.OrbitHost`; an unsupported host sets `Addon.incompatibleOrbit`, and an absent one leaves Compass
standalone. `../../Plugin/Plugin.xml` loads `Orbit.lua` between standalone services and controller construction. The
bridge registers the real `Orbit_Compass` plugin (`Bridge.CreateController`), its Visibility Engine row and the
`CompassLocations` collection, provides Strata Engine layers and frame persistence, and rebinds `Services`:
`Engine.Pixel`, `Orbit.Tooltip`/`TooltipHide`, `Orbit.Profiler`, Orbit's media fonts, `Orbit.Skin:SkinText`,
`Orbit:GetTheme("Font")`, `Orbit:IsEditMode()` and `SecretValueUtils.IsSecret`. The later `../Integrations.xml` loads
`OrbitCanvas.lua` after navigation and controller declarations to supply Canvas text drafts for the arrow. Product
navigation and formatting remain outside this module.

Search places reach Orbit through LibOrbitSearch rather than this bridge; see `../README.md`. Presentation hooks resolve
Orbit UI Chat from Orbit's private media catalog, while standalone Compass uses its own private catalog. Both resolve
that name to Blizzard's locale-aware font on Korean and Chinese clients.

## Gotchas
- An absent host uses standalone services. An unsupported host or an existing bundled Compass pauses startup, preserving
  the old controller, commands and bindings. Compatible Retail and Forever hosts use the same bridge; Compass's client
  policy still gates individual Forever sources.
- A hosted Compass is always active when the addon is installed and enabled. Orbit profile disable flags are ignored,
  and the shared app shell does not register a redundant Blizzard AddOns category or Enabled checkbox.
- Preserve `Orbit_Compass`, both settings indices and the historical Orbit migration. Do not flatten Orbit
  profile/Canvas state into the standalone store.
- Hosted settings share tab state between ribbon and arrow; the host's `SchemaBuilder` validates selection when switching.
  Tab reset preserves frame placement; the explicit position action keeps that separate ownership.
- The bridge registers the shared Points renderer on the host layout. Points reset clears supported rows' area/alternate
  choices and legacy preferences; unsupported client rows retain their values.
- The bridge must load before any feature caches service hooks or the controller. Canvas needs that controller, so it
  belongs to the later integration phase.

## Secrets
The bridge rebinds `Services.IsSecret` to `Orbit.SecretValueUtils.IsSecret`, so hosted gates report their source labels
through Orbit's secret-debug helper; it reads no secret values itself.

## References
`../README.md`, `../../Plugin/README.md`, `../../Config/README.md`; Orbit `Core/Plugin/README.md` and
`Core/Plugin/ExternalUIHost.lua`.
