# Compass landmark sources

## Description

Native readers for the world landmark catalog and single-map pin lookup.

## Purpose

Keep client policy, list readiness and record admission consistent across readers.

## Implementation

`CompassLandmarkMaps.lua` owns hierarchy and place geometry. `CompassLandmarkAreaPOIs.lua` claims area POI IDs
in source order. `CompassLandmarkTravel.lua` reads fixed taxi and graveyard locations.
`CompassLandmarkActivities.lua` reads dig sites, task quests and invasions when client policy allows them.
`CompassLandmarkRead.lua` handles list readiness and static replay. `CompassLandmarkRecord.lua` admits points.
`CompassLandmarkSources.lua` calls the same readers for the catalog and direct pin lookup.

## Gotchas

Off-map entrances and links can still claim an ID. A categorized POI claims its ID before the generic list reads it.
An unavailable list does not fill the static cache. Direct pin lookup borrows no catalog cache.
Keep checkpoints after native reads and inside loops so partial lists can yield within the catalog's existing budget.

## References

`../README.md`, `../../Discovery/README.md`, `../../../.scripts/README.md`.
