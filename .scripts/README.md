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
identity/widget registration and LibOrbitSearch revision 2 with provider contract 1; Events requires UI API 1.11 and
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

`check-client-features.py` checks client families, withheld APIs, partial data, retained preferences, destination
provenance, query-local map-read sharing/recovery, Navigation route guidance, stale actions and readiness, including
event storms at different frame rates. Run `python .scripts/check-client-features.py`.

`check-landmark-budget.py` exercises large synthetic catalogs, costly empty native lists, deterministic work bounds,
pause/resume, cancellation/root replacement, equivalent publication, balanced phase spans across yields, unindexed
first-build search cadence and aged refreshes that skip fixed sources and keep the background budget under focus. Run
`python .scripts/check-landmark-budget.py`; native map calls and final string concatenation remain indivisible, so these
bounds do not certify an in-game millisecond limit.

`check-resources.py` drives live resources through that capability double: version admission, Retail and standalone
silence, allocation-free unchanged polls, refinement without gaps, failure backoff, ownership release and auto-advance
latency equal to the empty baseline. Rendering cases cover mask/ring geometry, heading reservation, pooled-slot reuse
and actionable overlap groups. Orbit's producer suite checks the same contract against its scanner, so neither CI needs
the other repository; native detection, CPU and heap still need in-game verification. Release CI runs all three suites.

## Gotchas
- Compass pins verified UI 1.15/API 1.18 and Search 1.5/revision 8 releases. Linked checks do not establish release
  delivery; validate ordinary fetched packages. The automatic latest-release resolver is not implemented.
- `fetch-libs.py` and `check-package.py` remain byte-identical between both addon repositories; keep their changes
  synchronized. `check-client-features.py` is product-specific despite sharing its name with Events' suite.
- Compilation and static API checks cannot validate combat permissions, native ownership, taint or rendering.
  Dynamically assembled asset names still need client verification.
- Fetches use configured Git credentials without an interactive prompt. No token is written into `.pkgmeta` or the
  scripts.

## References
`../README.md`, `../.pkgmeta`, `../.github/workflows/README.md`, `../.github/workflows/release.yml`.
