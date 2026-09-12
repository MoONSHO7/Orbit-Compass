# Compass assets

## Description
The addon-list logo, gold destination arrow and note-description font shipped with this addon.

## Purpose
Keep navigation art and typography available without Orbit installed.

## Implementation
`Orbit.png` embeds the suite logo locally. `Source/orbit-compass-arrow.svg` is the editable arrow master; workspace `.scripts/make-compass-arrow.py` renders the shipped 64×64 RGBA `orbit-compass-arrow.tga`, pointing up at zero rotation. Services resolve asset paths from the addon directory. `PTSansNarrow.ttf` is the unmodified PT Sans Narrow font used by Orbit, bundled with its embedded license in `PTSansNarrow-OFL.txt`. Standalone note descriptions use this copy; the host bridge uses Orbit's media registration. Marker selection uses Blizzard atlases.

## Gotchas
The baked gold/amber art uses a white vertex tint and fits its rotation circle. Installing a new loose texture can require a client restart before it is available. `Source/` is excluded from release packages.

## References
Workspace `.scripts/make-compass-arrow.py`.
