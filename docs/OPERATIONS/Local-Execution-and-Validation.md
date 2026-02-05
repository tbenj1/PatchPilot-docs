# Local Execution & Validation

This guide shows how to execute PatchPilot locally (PowerShell 7) and validate that the **expected evidence, artifacts, and final reports** were produced.

> Scope: Local, interactive developer validation.
>
> RMM note: RMM tools typically run non-interactively. The same run command applies, but you should use your RMM's working directory controls and run as an elevated account when required.

---

## Prerequisites

- **PowerShell 7** installed (PatchPilot is PowerShell 7-only).
- A local working copy of the PatchPilot repo.
- For developer testing only: you may need a **Process-scoped** execution policy bypass (does not change system policy) and to remove Mark-of-the-Web from files extracted from a ZIP.

---

## Full local run + hard validation

Run this entire block in **pwsh**:

```powershell
# ===== PatchPilot: Full local real run + validation =====
$repo = "A:\\Career Advancement\\Professional Projects\\PatchPilot\\PatchPilot\\PatchPilot"
Set-Location $repo

# Dev-only: avoid unsigned/MOTW blocking for this session
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
Get-ChildItem -Path $repo -Recurse -File | Unblock-File -ErrorAction SilentlyContinue

# Import module
Import-Module .\\src\\PatchPilot.Engine\\PatchPilot.Engine.psd1 -Force
Get-Command Invoke-PatchPilotRun | Out-Null

# Run (NON-TestMode)
$code = Invoke-PatchPilotRun `
  -OutputRoot "$env:LOCALAPPDATA\\PatchPilot" `
  -ConfigPath ".\\examples\\configs\\lab\\NoOp.json" `
  -TenantId "MSP001" -ClientId "ACME" -SiteId "HQ" -DeviceId $env:COMPUTERNAME

# Identify newest run
$latest = Get-ChildItem "$env:LOCALAPPDATA\\PatchPilot\\Runs" -Directory |
  Sort-Object LastWriteTime -Descending | Select-Object -First 1
$runId = Split-Path -Leaf $latest.FullName

# Validate minimum expected artifacts (success path)
$mustExist = @(
  (Join-Path $latest.FullName "run.json"),
  (Join-Path $latest.FullName "Logs\\Events.jsonl"),
  (Join-Path $latest.FullName "Artifacts\\UpdateCatalog\\$runId\\catalog.json"),
  (Join-Path $latest.FullName "Reports\\final-report.json"),
  (Join-Path $latest.FullName "Reports\\final-report.html")
)
$missing = $mustExist | Where-Object { -not (Test-Path $_) }

# Parse events + fail if any Error/Fatal
$eventsPath = Join-Path $latest.FullName "Logs\\Events.jsonl"
$events = Get-Content $eventsPath | ForEach-Object { try { $_ | ConvertFrom-Json } catch { $null } } | Where-Object { $_ }
$bad = $events | Where-Object { $_.Level -in @("Error","Fatal") }

# Print result summary
[pscustomobject]@{
  ExitCode     = $code
  RunId        = $runId
  RunPath      = $latest.FullName
  MissingPaths = if ($missing) { $missing -join "; " } else { "" }
  ErrorCount   = @($bad).Count
  Catalog      = (Join-Path $latest.FullName "Artifacts\\UpdateCatalog\\$runId\\catalog.json")
  FinalJson    = (Join-Path $latest.FullName "Reports\\final-report.json")
  FinalHtml    = (Join-Path $latest.FullName "Reports\\final-report.html")
}

# Hard assertions for a true "full real test" pass
if ($code -ne 0) { throw "FAIL: ExitCode=$code (RunId=$runId)" }
if ($missing) { throw ("FAIL: Missing expected artifacts: " + ($missing -join "; ")) }
if ($bad) {
  $bad | Select-Object -First 10 TimeUtc, Level, EventName, Message | Format-Table -AutoSize
  throw "FAIL: Run contains Error/Fatal events (RunId=$runId)."
}

"PASS: Full real run succeeded (RunId=$runId ExitCode=$code)"
```

---

## Single-command run (RMM-friendly quoting)

If you need a single line (e.g., to paste into an RMM script step), this style avoids the common quoting pitfall with `$env:LOCALAPPDATA` and backslashes:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -Command '
  Set-Location "A:\\Career Advancement\\Professional Projects\\PatchPilot\\PatchPilot\\PatchPilot";
  Import-Module .\\src\\PatchPilot.Engine\\PatchPilot.Engine.psd1 -Force;
  Invoke-PatchPilotRun -OutputRoot ($env:LOCALAPPDATA + "\\\\PatchPilot") -ConfigPath ".\\examples\\configs\\lab\\NoOp.json" -TenantId "MSP001" -ClientId "ACME" -SiteId "HQ" -DeviceId $env:COMPUTERNAME
'
```

---

## Troubleshooting: "not digitally signed" on import

If you see:

- `... cannot be loaded. The file ... is not digitally signed ...`

That means this host is enforcing signature checks for the current session/policy.

For developer testing, use **process-scope** bypass (does not change your machine/user policy) and remove Mark-of-the-Web:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
Get-ChildItem -Path $repo -Recurse -File | Unblock-File -ErrorAction SilentlyContinue
```

For enterprise deployments, use proper code signing and an execution policy aligned with your organization's requirements.

---

## What to check after a run

The run output root uses this structure:

- `Runs/<RunId>/run.json` (run metadata)
- `Runs/<RunId>/Logs/Events.jsonl` (JSONL events)
- `Runs/<RunId>/Artifacts/UpdateCatalog/<RunId>/catalog.json` (update discovery evidence)
- `Runs/<RunId>/Reports/final-report.json` and `final-report.html` (final report outputs)

If any of these are missing on a successful exit code, treat it as a contract violation.
