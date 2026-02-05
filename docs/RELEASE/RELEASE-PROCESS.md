# Release Process

This process exists to keep PatchPilot:
- deterministic
- RMM-safe (non-interactive)
- contract-aligned (schemas + exit codes)
- auditable (evidence-first)

## Release artifacts

A release consists of:
- A deterministic ZIP built by `tools/Invoke-PackageRelease.ps1`
- A changelog entry in `CHANGELOG.md`
- A version bump in `src/PatchPilot.Engine/PatchPilot.Engine.psd1`

## CI gates

CI must run:
- `tools/Invoke-RepoComplianceScan.ps1`
- `tools/Invoke-PesterStages.ps1`

Any failure blocks release.

## Contract rules

- Additive changes to JSON artifacts are allowed in MINOR/PATCH releases.
- Removing fields, renaming keys, or changing meanings requires MAJOR.
- Exit code semantics are a contract (breaking changes require MAJOR).

## Packaging rules

- Never ship generated output directories.
- Never ship local assistant or editor state.
- Never ship ad-hoc diagnostics output.

See `docs/RELEASE/RELEASE-CHECKLIST.md` for the step-by-step.
