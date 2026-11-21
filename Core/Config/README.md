# Compass settings UI

## Description
Appearance schemas and the Points table shared by standalone and hosted settings.

## Purpose
Keep settings presentation separate from navigation, discovery and controller lifecycle.

## Implementation
`Config.xml` registers the hotkey and Points widgets before loading `CompassSettings.lua`, which supplies
`Addon.SettingsTabs`. `CompassPointHotkey.lua` owns native binding capture, its key in the layout's shared label and
value columns. `CompassPointsSettings.lua` owns the pooled visibility matrix, column explanations and each row's thin
native range slider; it reads and writes preferences through `../Discovery/CompassPointVisibility.lua`. A slider shows
Marker Range in grey until dragged, then gold; right-click clears the row's own range. Waypoint has no slider because a
waypoint shows at any distance. Appearance's Font picker stores an override face in `TextFont` for all Compass text, the
place title included; Default (`Orbit Default`, shared with Orbit and Events) clears it, so text follows Orbit UI alone
or Orbit's theme font when hosted, and Blizzard is the game's face. Standalone lists `Addon.Fonts.List()` through
`../CompassBoot.lua`'s media provider, hosted uses Orbit's picker. Place Names is a three-step slider (Off, Above,
Below) stored as `PlaceNames`.

The standalone application and the Orbit bridge both consume these schemas and widget registrations. Compass and Arrow
omit lifecycle toggles because WoW addon enablement owns availability. Arrow schemas use the component preferences and
distance formatting owned by `../Navigation/`.

Both surfaces use Layout, Appearance and Behaviour in that order, with Points appended for the ribbon. The ribbon's
Appearance adds Quest Level Range only while a compatible QuestieDB is loaded on Forever; schemas are rebuilt each time
settings open, so the row follows the addon without a stored flag. Scope appears in control hover help. Arrow
Behaviour owns Show Arrow, auto-advance, same-type routing, corpse recovery and native map tracking; Show Arrow is a
display preference on index 2, not a lifecycle toggle.
Auto-advance maps the existing mode to on/off; enabled modes use arrival-or-removal semantics. Same-type routing remains
visible but disabled while auto-advance is off, with the reason on hover; changing the parent retains the child's preference.

## Gotchas
- Tab resets retain frame positions. Compound component/distance settings clear only the owned field; Arrow Behaviour
  writes to its navigation controller's existing owner. Standalone Reset position remains a separate action.
- Both settings windows must use the same widget renderer and controller accessors. Standalone changes trigger
  application through the store callback; hosted changes explicitly request application.
- Points intersects all 20 definitions with the same client policy as Discovery/Search. GatherMate2, HandyNotes and Town
  Services (QuestieDB) also require their addon to be loaded, as does Forever's Available Quests: that client's offer
  APIs return no givers. Hovering a row's label shows its `tooltipKey`, or `foreverTooltipKey` where Forever's source
  differs (Zone Points of Interest, Available Quests). Hidden rows retain saved preferences and occupy no space; Forever
  Points reset preserves unsupported Retail rows. Filtering never persists false merely because the client lacks a
  feature.
- The font key is `TextFont`, never `Font`: Orbit inherits a plugin's `Font` from its theme and writes it there, so it
  would restyle all of Orbit. The standalone store accepts the name only because `Definition.valueTypes` declares it.
- Keybindings belong to the current WoW binding set, not the Compass profile. Capture stops on hide or combat entry, and
  failed assignment preserves the previous keys.
- Range sliders commit each snapped step like the Behaviour sliders. Their displayed value is set under an
  initialization guard, so opening Points never turns an inherited Marker Range into a saved row range.
- Controls, rows, range sliders and header hover regions are reused with their table. Hover uses the private layout
  tooltip; release must retire any visible tooltip and cell callbacks, and unbinds each slider from its row.
- The hotkey's temporary visibility mode is owned by Discovery. It must not add keyboard polling or settings reads to
  the render loop.

## References
`../README.md`, `../Discovery/README.md`, `../Navigation/README.md`, `../../Localization/README.md`; the
`orbit-settings`, `orbit-tooltips` and `pixel` skills.
