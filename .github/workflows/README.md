# Release workflow

## Description
Validated branch builds and versioned CurseForge/GitHub releases for Orbit Compass.

## Purpose
Keep incomplete runtime bundles and incompatible embedded libraries out of player releases.

## Implementation
`release.yml` validates the triggering checkout, fetches full commit pins from `.pkgmeta`, checks Lua 5.1 and the loaded library APIs, then builds with a pinned BigWigs packager and validates its materialized output. Branch builds retain a ZIP artifact for 14 days; artifact collection allows the hidden `.release` directory and selects only its ZIP files.

Successful `main` pushes choose the next `MAJOR.MINOR` tag, starting at `1.0`; later automatic releases increment the minor number. Stable tag pushes package that exact revision. Manual runs release only when targeting `main` or a stable tag. Other branches and pull requests only build.

The version tag is initially local to the runner and is pushed only after package validation. Publishing retains the validated package with `-o -c -e`, uploading to the TOC's CurseForge project ID and GitHub Releases. Uploaded GitHub assets are downloaded and compared with the local artifacts. The same run handles publication, so tags created with `GITHUB_TOKEN` do not need to trigger another workflow. LF bytes are preserved.

## Gotchas
- `CURSE_API_KEY` authorizes CurseForge upload; `ORBIT_PAT` supplies private-library read access through GitHub CLI's credential helper. The repository-scoped `GITHUB_TOKEN` publishes tags and GitHub releases. Checkout credentials are not persisted.
- Fork/Dependabot pull requests receive no private-library credentials and only report that full coverage is unavailable. This workflow never uses `pull_request_target`.
- Dependency pins select compatible pushed source snapshots, not versioned library releases. Source and staged-package validation check the exact fetched commits before tagging or uploading; local development junctions cannot substitute for these checks.
- Main/tag publication runs are serialized. A retry reuses a version already attached to its commit. If a GitHub release already exists, publication fails for human review: its existence cannot prove the CurseForge or asset uploads completed. After any failed upload, inspect both destinations before retrying, including when no GitHub release was created.
- The pinned packager deletes its package directory without `-o`, even when `-c` skips copying. Keep all three retention flags on the upload pass. Asset downloads catch packager asset failures that its exit status can miss.
- Both packager passes receive the selected stable tag explicitly; otherwise the packager can choose a newer nonstable tag attached to the same commit.
- Source and package checks cannot certify WoW rendering, combat protection or taint. In-game acceptance and merging to `main` remain with the human.

## References
[Project](../../README.md), [validation tools](../../.scripts/README.md), [package metadata](../../.pkgmeta), [BigWigs packager](https://github.com/BigWigsMods/packager).
