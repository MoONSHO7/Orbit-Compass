# Compass artwork

## Description
The addon-list logo and gold destination arrow texture owned by this addon.

## Purpose
Keep navigation art available without Orbit installed.

## Implementation
`Orbit.png` embeds the suite logo locally so the addon list needs no Orbit installation. `Source/orbit-compass-arrow.svg` is the editable arrow master. Workspace `.scripts/make-compass-arrow.py` renders the shipped 64×64 RGBA `orbit-compass-arrow.tga`, pointing up at zero rotation. The product services resolve its path from the actual addon directory. Marker selection continues to use Blizzard atlases.

## Gotchas
The baked gold/amber art uses a white vertex tint and fits its rotation circle. Installing a new loose texture can require a client restart before it is available. `Source/` is excluded from release packages.

## References
Workspace `.scripts/make-compass-arrow.py`.
