# Standalone package validation

## Description
Dependency fetching and runtime package validation shared by the independent Compass and Status Widget repositories.

## Purpose
Keep development library links convenient while rejecting incomplete or incompatible release bundles.

## Implementation
`fetch-libs.py` parses immutable GitHub externals from `.pkgmeta`, fetches exact commits and archives their declared runtime subdirectories. Omitted `path` means the repository root. Existing junctions and symlinks are preserved; `--force` refreshes only ordinary directories.

`check-package.py` walks the TOC/XML load order, including Bindings.xml. It strips development blocks, compiles Lua 5.1, checks product metadata/assets and required APIs in the loaded libraries. Compass requires UI API 1.8 with client identity/widget registration and LibOrbitSearch provider APIs; Status requires UI API 1.6 and picker revision 10. Interface metadata accepts distinct positive integers including Retail 120100; this does not certify loader behavior. API checks inspect declarations without executing addon code.

Run `python .scripts/check-package.py` for linked sources. Release CI fetches libraries, runs `check-package.py --release`, then checks the materialized package with `--root .release/ADDON --release`. Release mode requires Compass Search/LibStub externals and rejects filesystem links; a different root also requires substituted version metadata. Python needs `lupa==2.8`.

`check-client-features.py` loads real Compass policy, collectors, scheduler, map scope, Search, navigation and UI client/store code into Lua 5.1. It checks client families, withheld APIs, partial data, retained preferences, destination provenance, stale actions and source readiness. Run `python .scripts/check-client-features.py`; workspace `develop/search-bridge/compass_provider_harness.py` covers the shared Search integration. Neither simulates native rendering or security.

## Gotchas
- Compass pins verified UI 1.3/API 1.8 and Search 1.0/revision 3 releases. Linked checks do not establish release delivery; validate ordinary fetched packages. The automatic latest-release resolver is not implemented.
- The scripts remain byte-identical between both addon repositories. Keep changes synchronized.
- Compilation and static API checks cannot validate combat permissions, native ownership, taint or rendering. Dynamically assembled asset names still need client verification.
- Fetches use configured Git credentials without an interactive prompt. No token is written into `.pkgmeta` or the scripts.

## References
`../README.md`, `../.pkgmeta`, `../.github/workflows/release.yml`.
