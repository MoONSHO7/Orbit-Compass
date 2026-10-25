# Standalone package validation

## Description
Dependency fetching, runtime package validation and the Compass client-boundary suite.

## Purpose
Keep development library links convenient while rejecting incomplete or incompatible release bundles, and exercise
client policy without a WoW client.

## Implementation
`fetch-libs.py` parses immutable GitHub externals from `.pkgmeta`, fetches exact commits and archives their declared
runtime subdirectories. Omitted `path` means the repository root. Existing junctions and symlinks are preserved;
`--force` refreshes only ordinary directories.

`check-package.py` walks the TOC/XML load order, including Bindings.xml. It strips development blocks, compiles Lua 5.1,
checks product metadata/assets and required APIs in the loaded libraries. Compass requires UI API 1.11 with client
identity/widget registration and LibOrbitSearch revision 2 with provider contract 1; Status requires UI API 1.11 and
picker revision 10. Interface metadata accepts distinct positive integers including Retail 120100; this does not certify
loader behavior. API checks inspect declarations without executing addon code.

Run `python .scripts/check-package.py` for linked sources. Release CI fetches libraries, runs
`check-package.py --release`, then checks the materialized package with `--root .release/ADDON --release`. Release mode
requires Compass Search/LibStub externals and rejects filesystem links; a different root also requires substituted
version metadata. Python needs `lupa==2.8`.

`compass_harness.py` is the suites' shared Lua 5.1 client: native namespace doubles, the loaded Compass files and the
LibOrbitUI client/store, read from the sibling `../Orbit-Libs/LibOrbitUI/LibOrbitUI-1.0` path (the workspace checkout
locally and, in the workflow's `suites` job, a symlink to the fetched `Libs/LibOrbitUI-1.0`). It also holds a double of
Orbit's documented resource-observation capability; it simulates no native rendering or security. Its `table.freeze`
double records frozen tables so `table.sort` rejects them, as the strictest client may.

`check-client-features.py` loads real Compass policy, collectors, scheduler, map scope, Search, navigation and
LibOrbitUI client/store code into Lua 5.1. It checks client families, withheld APIs, partial data, retained preferences,
destination provenance, query-local map-read sharing/recovery, Navigation route guidance, stale actions and readiness, including event storms at
different frame rates. Hosted resource cases cover borrowed-array mutation, expiry, bounded identity retention and
display-only action exclusions. Run `python .scripts/check-client-features.py`; it reads LibOrbitUI from the sibling
`../Orbit-Libs/LibOrbitUI/LibOrbitUI-1.0` path, which is the workspace checkout locally and, in the workflow's `suites`
job, a symlink to the fetched `Libs/LibOrbitUI-1.0`. It does not simulate native rendering or security.

`check-landmark-budget.py` exercises large synthetic catalogs, costly empty native lists, deterministic work bounds,
pause/resume, cancellation/root replacement, equivalent publication, balanced phase spans across yields and unindexed
first-build search cadence. Run `python .scripts/check-landmark-budget.py`; native map calls and final string
concatenation remain indivisible, so these bounds do not certify an in-game millisecond limit.
Release CI runs both suites.

`check-resource-audit.py` exercises live-resource publication, hidden resume, paused comparisons, mixed marker actions
and Retail isolation. Pooled mask/ring checks cover scale geometry, unchanged setter counts, bounded region allocation
and released marker ownership through full-pool replacements and clear/reopen cycles.
`check-resource-performance.py` measures bounded work, unchanged reuse and retained ownership through dense replacements
and enable/disable cycles. Empty-resource checks bound job allocations and provider reads while exercising projection
recovery and unknown counts. Both reuse the client suite's harness and run in release CI.

## Gotchas
- Compass pins verified UI 1.14/API 1.17 and Search 1.4/revision 7 releases. Linked checks do not establish release
  delivery; validate ordinary fetched packages. The automatic latest-release resolver is not implemented.
- `fetch-libs.py` and `check-package.py` remain byte-identical between both addon repositories; keep their changes
  synchronized. `check-client-features.py` is product-specific despite sharing its name with Status's suite.
- Compilation and static API checks cannot validate combat permissions, native ownership, taint or rendering.
  Dynamically assembled asset names still need client verification.
- Fetches use configured Git credentials without an interactive prompt. No token is written into `.pkgmeta` or the
  scripts.

## References
`../README.md`, `../.pkgmeta`, `../.github/workflows/README.md`, `../.github/workflows/release.yml`.
