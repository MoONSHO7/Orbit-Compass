# Standalone package validation

## Description
Dependency fetching and runtime package validation shared by the independent Compass and Status Widget repositories.

## Purpose
Keep development library links convenient while rejecting incomplete or incompatible release bundles.

## Implementation
`fetch-libs.py` parses immutable GitHub externals from `.pkgmeta`, fetches exact commits and archives their declared runtime subdirectories. Omitted `path` means the repository root. Existing junctions and symlinks are preserved; `--force` refreshes only ordinary directories.

`check-package.py` derives the addon TOC from `.pkgmeta` and walks its TOC/XML load order, including automatic Bindings.xml. It strips do-not-package blocks, compiles Lua with `lupa.lua51`, checks metadata (including the product's CurseForge project ID) and straightforward asset references, and verifies the required APIs exist inside the loaded library closure. Both addons require LibOrbitUI 1.4; Status Widget also requires picker revision 10. API checks inspect declarations without executing addon code.

Run `python .scripts/check-package.py` for linked development sources. Release CI runs `fetch-libs.py`, then `check-package.py --release`, and finally `check-package.py --root .release/ADDON --release` after packaging. `--release` rejects filesystem links; a different `--root` also requires the source version token to have been substituted. Python needs `lupa==2.8`.

## Gotchas
- Pins select pushed source commits providing UI API 1.4 and, where needed, picker revision 10. Versioned library releases remain unpublished; validation checks the actual fetched runtime rather than relying on a tag or local development link.
- The scripts remain byte-identical between both addon repositories. Keep changes synchronized.
- Compilation and static API checks cannot validate combat permissions, native ownership, taint or rendering. Dynamically assembled asset names still need client verification.
- Fetches use configured Git credentials without an interactive prompt. No token is written into `.pkgmeta` or the scripts.

## References
`../README.md`, `../.pkgmeta`, `../.github/workflows/release.yml`.
