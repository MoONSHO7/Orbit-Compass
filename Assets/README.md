# Compass assets

## Description
The addon-list logo, gold destination arrow and private interface fonts shipped with this addon.

## Purpose
Keep navigation art and typography available without Orbit installed.

## Implementation
`Orbit.png` embeds the suite logo locally. The workspace-root `.scripts/make-compass-arrow.py` (outside this repository)
owns the arrow: it models the outline, rim, inset and gem as a relief, lights it in Blender's Cycles, adds the soft
shadow, and packs the shipped 256×256 straight-alpha `orbit-compass-arrow.tga`, pointing up at zero rotation.
`Core/Plugin/CompassServices.lua` resolves asset paths from the addon directory. Standalone ribbon text uses Orbit UI
and search uses Orbit UI Chat; `Core/Foundation/CompassFonts.lua` resolves those names to the bundled Western/Cyrillic
faces under `Fonts/` outside Korean and Chinese locales, where Blizzard's locale-aware `STANDARD_TEXT_FONT` is used
instead. The bundled faces' OFL notices live in `Fonts/licenses/`. `PTSansNarrow.ttf` remains the note-description
face, with its license in `PTSansNarrow-OFL.txt`. Hosted mode resolves the same private font names through Orbit.
Marker selection uses Blizzard atlases.

## Gotchas
- The baked art uses a white vertex tint; its shadow fades out inside the rotation circle. Every arrow
  `SetTexture` passes `ARROW_TEXTURE_FILTER` (`TRILINEAR`): without mipmaps the 256-pixel art aliases at small sizes.
- Installing a new loose texture or font can require a client restart before it is available.
- The bundled faces remain private and are never registered with LibSharedMedia.

## References
`../Core/Foundation/README.md` (`CompassFonts.lua`, `CompassArtwork.lua`), `../Core/Plugin/README.md`; the
workspace-root `.scripts/make-compass-arrow.py`.
