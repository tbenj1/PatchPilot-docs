# Release Checklist

Use this checklist to produce a deterministic, MSP/RMM-safe PatchPilot release.

## 1) Pre-flight

- [ ] Confirm you are using **PowerShell 7.x** (`pwsh`) for all checks.
- [ ] Confirm the repo tree is clean (no local artifacts staged):
  - [ ] `_site/` absent
  - [ ] `test-output/` absent
  - [ ] `tests/_diag-out/` absent

## 2) Compliance gates

- [ ] Run repository compliance scan:

```powershell
pwsh -NoProfile -NonInteractive -File .\tools\Invoke-RepoComplianceScan.ps1
```

- [ ] Run the full test suite (all stages):

```powershell
pwsh -NoProfile -NonInteractive -File .\tools\Invoke-PesterStages.ps1
```

- [ ] Review any new/changed exit codes and ensure they match `docs/API/Exit-Codes.md`.

## 3) Version + changelog

- [ ] Determine the version bump per `docs/RELEASE/VERSIONING.md`.
- [ ] Update module version in:
  - [ ] `src/PatchPilot.Engine/PatchPilot.Engine.psd1`
- [ ] Update `CHANGELOG.md`:
  - [ ] Move items from **Unreleased** into a new version section
  - [ ] Add the release date

## 4) Deterministic packaging

- [ ] Build the deterministic release ZIP:

```powershell
pwsh -NoProfile -NonInteractive -File .\tools\Invoke-PackageRelease.ps1 -RepoRoot . -OutFile .\PatchPilot-release.zip
```

- [ ] (Optional) Confirm deterministic output by running packaging twice and comparing hashes.

## 5) Release publication

- [ ] Tag the release in git (example):

```powershell
git tag -a vX.Y.Z -m "PatchPilot vX.Y.Z"
git push origin vX.Y.Z
```

- [ ] Create release notes using `CHANGELOG.md`.
- [ ] Attach `PatchPilot-release.zip` to the release.

## 6) Post-release

- [ ] Run a smoke run in a clean environment (RMM-like) using a known lab config.
- [ ] Confirm artifacts are produced and exit codes are correct.
