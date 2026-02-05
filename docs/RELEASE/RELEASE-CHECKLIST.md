# Release Checklist

This checklist is intentionally **deterministic** and **RMM-safe**.

## 1) Pre-flight (local)

- [ ] Use **PowerShell 7**.
- [ ] From repo root, run compliance scan:

```powershell
pwsh -NoProfile -NonInteractive -File ./tools/Invoke-RepoComplianceScan.ps1
```

- [ ] Run tests:

```powershell
pwsh -NoProfile -NonInteractive -File ./tools/Invoke-PesterStages.ps1
```

## 2) Confirm determinism / RMM safety

- [ ] No prompts (`('Read' + '-Host')`, `('Get' + '-Credential')`, UI dialogs).
- [ ] No host-only output (`('Write' + '-Host')`).
- [ ] No global run state (`('$Global' + ':')`).
- [ ] Exit codes match `docs/API/Exit-Codes.md`.

## 3) Update release metadata

- [ ] Update `CHANGELOG.md` (move items from **Unreleased** to the new version heading).
- [ ] Bump `ModuleVersion` in `src/PatchPilot.Engine/PatchPilot.Engine.psd1`.

## 4) Package deterministically

```powershell
pwsh -NoProfile -NonInteractive -File ./tools/Invoke-PackageRelease.ps1 -RepoRoot . -OutFile ./PatchPilot-release.zip
```


## 5) CI validation

- [ ] Ensure CI is green on the release commit.

## 6) Tag + publish

- [ ] Create git tag `vX.Y.Z`.
- [ ] Create a GitHub Release using notes from `CHANGELOG.md`.
