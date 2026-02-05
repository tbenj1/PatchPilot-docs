# Release Process

This document defines how PatchPilot releases are produced and verified.

## Goals

- Deterministic, reproducible release ZIPs
- MSP/RMM-safe non-interactive behavior
- Evidence-first: CI results + artifacts support every release

## Inputs

- Repository state at a specific commit
- CI result for that commit (workflow: `.github/workflows/ci.yml`)
- Deterministic packaging tool: `tools/Invoke-PackageRelease.ps1`

## Outputs

- `PatchPilot-release.zip` created by deterministic packaging
- A SemVer tag (`vX.Y.Z`)
- Updated `CHANGELOG.md`

## Procedure

1. Follow `docs/RELEASE/RELEASE_CHECKLIST.md`.
2. Ensure the commit you tag is exactly the commit you packaged.
3. Publish release notes derived from `CHANGELOG.md`.

## Determinism contract

The release ZIP must be reproducible from the same repository state by running `tools/Invoke-PackageRelease.ps1`. If packaging output changes between runs, treat it as a release blocker.

## Emergency fixes

For urgent production fixes:
- Create a patch branch from the last tag.
- Apply the minimal fix.
- Run all gates.
- Release as a PATCH bump.
