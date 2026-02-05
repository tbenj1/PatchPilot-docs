# PatchPilot User Guide

## Overview

PatchPilot.Engine is a PowerShell 7 patch orchestration engine designed for MSP multi-tenant environments. It provides auditable, evidence-based patching with safe resume/retry capabilities and deterministic exit codes for RMM integration.

**Referenced artifacts:**
- Module manifest: `src/PatchPilot.Engine/PatchPilot.Engine.psd1`
- Public functions: `src/PatchPilot.Engine/Public/*.ps1`
  - Invoke-PatchPilotRun
  - Get-PatchPilotExitCodes
  - Get-PatchPilotVersion
  - Get-PatchPilotExitCodeFromEvidence
- Config examples: `examples/configs/*.json`
- Schemas: `data/schemas/*.schema.json`

## Prerequisites

- **PowerShell 7.0+** (required)
- **Windows 10/11** or **Windows Server 2016+**
- **Administrator privileges** (required for patch operations)
- **Network access** to Windows Update endpoints

## Installation

1. Download the latest release
2. Extract to `C:\Program Files\PatchPilot`
3. Verify PowerShell 7:

```powershell
$PSVersionTable.PSVersion  # Should show 7.x.x
```

4. Import module:

```powershell
Import-Module "C:\Program Files\PatchPilot\src\PatchPilot.Engine\PatchPilot.Engine.psd1"
```

## Basic Usage

### Simple Run

```powershell
Invoke-PatchPilotRun -OutputRoot "C:\PatchPilot\Output"
```

### With Client Profile

```powershell
Invoke-PatchPilotRun `
    -OutputRoot "C:\PatchPilot\Output" `
    -TenantId "MSP-001" `
    -ClientId "ClientABC" `
    -SiteId "HQ" `
    -DeviceId "WS-001" `
    -PolicyProfileId "Production"
```

### Test Mode (Dry-Run)

```powershell
Invoke-PatchPilotRun -OutputRoot "C:\PatchPilot\Test" -TestMode
```

## Exit Codes

Implemented in `src/PatchPilot.Engine/Public/Get-PatchPilotExitCodes.ps1`:

```powershell
Get-PatchPilotExitCodes

# 0   : Success
# 100 : PartialSuccess
# 150 : RebootRequired
# 170 : ConcurrencyLock
# 210 : InstallFailure
# 220 : ValidationFailure
# 230 : DiagnosticsFailure
# 240 : ReportingFailure
```

## Common Workflows

### Pre-Production Test

```powershell
Invoke-PatchPilotRun `
    -OutputRoot "C:\PatchPilot\Test" `
    -PolicyProfileId "PreProduction" `
    -TestMode
```

### Maintenance Window Patching

```powershell
$startTime = Get-Date
$outputRoot = "C:\PatchPilot\Output\$(Get-Date -Format 'yyyy-MM-dd')"
$exitCode = Invoke-PatchPilotRun -OutputRoot $outputRoot

[PSCustomObject]@{
    Timestamp = $startTime
    Device    = $env:COMPUTERNAME
    ExitCode  = $exitCode
    Duration  = (Get-Date) - $startTime
} | Export-Csv "\server\logs\patch-history.csv" -Append
```

## Output Structure

PatchPilot writes *per-run* evidence under `OutputRoot\Runs\<RunId>\` and writes *per-device persistent state* under `OutputRoot\State\Tenants\...\Devices\...`.

### Per-run evidence root

```
OutputRoot\
└── Runs\
    └── <RunId>\                       # GUID; one folder per execution/resume chain
        ├── artifact-index.json
        ├── manifest.json
        ├── run.json
        ├── Logs\
        │   ├── Events.jsonl
        │   └── install-summary.jsonl
        ├── Artifacts\
        │   ├── Baseline\<RunId>\
        │   │   └── baseline.json
        │   ├── Snapshot\<RunId>\
        │   │   └── snapshot.json
        │   ├── UpdateCatalog\<RunId>\
        │   │   └── catalog.json
        │   └── Diagnostics\
        │       └── LightDiag\<RunId>\  # optional/required per policy
        ├── Reports\
        │   ├── pre-validation.json
        │   ├── post-validation.json
        │   ├── regressions.json
        │   ├── diff-report.json
        │   ├── final-report.json
        │   ├── final-report.html
        │   └── redaction-log.json
        ├── Telemetry\
        └── State\
            └── state.json              # per-run checkpoint/state machine
```

### Per-device persistent state root (multi-tenant)

PatchPilot maintains a *persistent* device state folder so that:
- concurrent runs can be prevented safely
- reboot/resume can continue the same RunId
- diagnostics throttling can be enforced across runs

```
OutputRoot\
└── State\
    └── Tenants\<TenantId>\Clients\<ClientId>\Sites\<SiteId>\Devices\<DeviceId>\
        ├── lock.json                       # concurrency guard (exclusive lock)
        ├── reboot-required.json            # reboot cookie (written by Phase06)
        ├── reboot-required.consumed.*.json # archived cookies (audit trail)
        └── diagnostics-run-history.json    # LightDiag throttling history (bounded)
```


## Reading Reports

### HTML Report

```powershell
$reportPath = Get-ChildItem "C:\PatchPilot\Output\Runs\*\Reports\final-report.html" | Select -First 1
Start-Process $reportPath
```

### JSON Report

```powershell
$report = Get-Content "C:\PatchPilot\Output\Runs\*\Reports\final-report.json" | ConvertFrom-Json
$report.InstallSummary | Where installed -eq $true | Format-Table kb, title, classification
```

### Install Summary

```powershell
Get-Content "C:\PatchPilot\Output\Runs\*\Logs\install-summary.jsonl" | ForEach-Object {
    $_ | ConvertFrom-Json
} | Where installed -eq $false | Format-Table kb, title, hresult
```

## Configuration

Policy files in `examples/configs/`:
- ClientProfile.json
- UpdatePolicy.json
- AppValidationPolicy.json
- BackupPolicy.json
- diagnostics config (top-level "diagnostics" block)
- ReportingPolicy.json

### Policy Precedence

```
Global → Tenant → Client → Site → Device
```

## Resume After Reboot

```powershell
# After reboot, run same command
Invoke-PatchPilotRun -OutputRoot "C:\PatchPilot\Output"
# Automatically resumes at Phase07
```

## Concurrency Protection

```powershell
# Returns 170 if another run active
$exitCode = Invoke-PatchPilotRun -OutputRoot "C:\PatchPilot\Output"
```

## See Also

- [Troubleshooting](./Troubleshooting.md)
- [Runbook](./Runbook-Patch-Cycle.md)
- [RMM Integration](./RMM-Integration.md)
- [Policy Authoring](../GUIDES/Policy-Authoring.md)
