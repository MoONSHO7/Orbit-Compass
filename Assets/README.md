# Compass assets

## Description
The addon-list logo, gold destination arrow and private interface fonts shipped with this addon.

## Purpose
Keep navigation art and typography available without Orbit installed.

## Implementation
`Orbit.png` embeds the suite logo locally. `Source/orbit-compass-arrow.svg` is the editable arrow master; workspace `.scripts/make-compass-arrow.py` renders the shipped 64×64 RGBA `orbit-compass-arrow.tga`, pointing up at zero rotation. Services resolve asset paths from the addon directory. Standalone ribbon text uses Orbit UI and search uses Orbit UI Chat; locale-specific Korean, Simplified Chinese and Traditional Chinese binaries replace the Western/Cyrillic files when required. The faces and their OFL notices live under `Fonts/`. `PTSansNarrow.ttf` remains the note-description face, with its license in `PTSansNarrow-OFL.txt`. Hosted mode resolves the same private font names through Orbit. Marker selection uses Blizzard atlases.

## Gotchas
The baked gold/amber art uses a white vertex tint and fits its rotation circle. Installing a new loose texture or font can require a client restart before it is available. The bundled faces remain private and are never registered with LibSharedMedia. `Source/` is excluded from release packages.

## References
Workspace `.scripts/make-compass-arrow.py`.
