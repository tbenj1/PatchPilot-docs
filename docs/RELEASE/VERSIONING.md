# Versioning Policy

PatchPilot uses **Semantic Versioning 2.0.0** (SemVer): `MAJOR.MINOR.PATCH`.

## Principles

- **Determinism first:** version bumps are not the only signal of change. A release must be reproducible from repository state and the deterministic packaging tool.
- **RMM safety:** releases must remain non-interactive and safe for unattended execution.
- **Contract clarity:** changes to public interfaces require explicit, documented version decisions.

## What counts as a public interface

Treat the following as public interface (breaking changes may require a MAJOR bump):

- Any exported PowerShell function signature (parameters, required/optional semantics)
- JSON schemas under `data/schemas/`
- Run output layout that downstream tooling depends on (paths, filenames, required artifacts)
- Exit code semantics

## Version bump rules

### PATCH (`x.y.Z`)
Use when the change is backwards compatible and does not alter contracts.

Examples:
- Bug fix with same contract/output schema
- Documentation updates
- Test changes
- CI / packaging tooling changes
- Internal refactors that do not change public interfaces

### MINOR (`x.Y.z`)
Use for backwards compatible feature additions.

Examples:
- New optional configuration fields (with defaults)
- New optional artifacts in output (additive)
- New phases or phase enhancements that do not change existing output contract

### MAJOR (`X.y.z`)
Use for breaking changes.

Examples:
- Removing or renaming exported functions
- Changing required config fields or JSON schema expectations
- Changing output folder layout or artifact names in a way that breaks downstream tooling
- Changing exit code meanings

## Where the version lives

- PowerShell module version: `src/PatchPilot.Engine/PatchPilot.Engine.psd1`
- Release notes: `CHANGELOG.md`

When preparing a tagged release, update both.

## Pre-release tags

If you use pre-release versions (optional), follow SemVer metadata conventions:
- `1.2.0-beta.1`
- `1.2.0-rc.1`

Pre-releases must still pass all CI gates.
