# CI

PatchPilot includes a simple CI workflow that runs:

- Repository compliance scan (forbidden tokens + approved verbs)
- Pester stage suite

See `.github/workflows/ci.yml`.

## Local equivalent

```powershell
pwsh -NoProfile -NonInteractive -File ./tools/Invoke-RepoComplianceScan.ps1
pwsh -NoProfile -NonInteractive -File ./tools/Invoke-PesterStages.ps1
```

## Deterministic packaging

```powershell
pwsh -NoProfile -NonInteractive -File ./tools/Invoke-PackageRelease.ps1 -RepoRoot . -OutFile ./PatchPilot-release.zip
```

## Release

For the full release procedure, see `docs/RELEASE/RELEASE_CHECKLIST.md`.
