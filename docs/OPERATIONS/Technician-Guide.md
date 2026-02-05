# Technician Guide

## Overview

This guide is for MSP technicians, NOC engineers, and help desk staff who deploy, operate, and troubleshoot PatchPilot in production environments. It provides practical procedures, quick-reference commands, and step-by-step remediation for common scenarios.

**Referenced Code:**
- Main engine: `src/PatchPilot.Engine/Public/Invoke-PatchPilotRun.ps1`
- Exit codes: `src/PatchPilot.Engine/Public/Get-PatchPilotExitCodes.ps1`
- Evidence evaluation: `src/PatchPilot.Engine/Public/Get-PatchPilotExitCodeFromEvidence.ps1`

---

## Prerequisites

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| PowerShell | 7.0 | 7.4+ |
| Windows | 10/Server 2016 | 11/Server 2022 |
| Privileges | Local Administrator | Local Administrator |
| Storage | 500 MB free | 2 GB free |
| Network | Windows Update endpoints | Windows Update + RMM endpoints |

**Verify PowerShell 7:**
```powershell
pwsh -NoProfile -Command '$PSVersionTable.PSVersion'
# Output should show 7.x.x
```

---

## Installation & Deployment

### Method 1: Manual Installation

```powershell
# 1. Create installation directory
New-Item -ItemType Directory -Path 'C:\Program Files\PatchPilot' -Force

# 2. Extract release archive
Expand-Archive -Path '.\PatchPilot-vX.X.X.zip' -DestinationPath 'C:\Program Files\PatchPilot'

# 3. Unblock files (if downloaded from internet)
Get-ChildItem -Path 'C:\Program Files\PatchPilot' -Recurse -File | Unblock-File

# 4. Verify module loads
pwsh -NoProfile -Command "Import-Module 'C:\Program Files\PatchPilot\src\PatchPilot.Engine\PatchPilot.Engine.psd1'; Get-PatchPilotVersion"
```

### Method 2: RMM Deployment

For automated RMM deployment, see [RMM Integration Guide](RMM-Integration.md).

**N-able Quick Deploy:**
```powershell
# From N-able script component
.\Deploy-PatchPilot.ps1 -Source 'GitHub' -InstallPath 'C:\Program Files\PatchPilot'
```

### Method 3: Intune/SCCM Package

1. Package the release ZIP with the module manifest
2. Use detection rule: `Test-Path 'C:\Program Files\PatchPilot\src\PatchPilot.Engine\PatchPilot.Engine.psd1'`
3. Deploy with SYSTEM context

---

## Configuration Essentials

### Required Configuration Files

| File | Purpose | Location |
|------|---------|----------|
| `config.json` | Master configuration (outputRoot, policy paths) | Deploy alongside module or RMM download |
| `UpdatePolicy.json` | Update classifications, deferrals, reboot settings | `examples/configs/UpdatePolicy.json` |
| `AppValidationPolicy.json` | Application health checks (HTTP, process, synthetic) | `examples/configs/AppValidationPolicy.json` |
| `ReportingPolicy.json` | Redaction settings for reports | Config directory |

### Minimal config.json

```json
{
  "outputRoot": "C:\\PatchPilot\\Output",
  "UpdatePolicyPath": "UpdatePolicy.json",
  "AppValidationPolicyPath": "AppValidationPolicy.json",
  "lockTtlMinutes": 120,
  "diagnostics": {
    "mode": "OnFailure",
    "required": false
  }
}
```

### Key Configuration Options

**UpdatePolicy.json** (`examples/configs/UpdatePolicy.json`):
```json
{
  "updateSettings": {
    "autoApprove": true,
    "classifications": ["Critical", "Important", "SecurityUpdates"],
    "excludedKBs": [],
    "deferralDays": 7
  },
  "rebootSettings": {
    "allowAutoReboot": false,
    "rebootDelayMinutes": 15
  }
}
```

**AppValidationPolicy.json** (`examples/configs/AppValidationPolicy.json`):
```json
{
  "CaptureHttpBodies": true,
  "applications": [
    {
      "name": "WebApp",
      "patterns": [
        { "type": "HealthEndpoint", "url": "https://example.com/health", "expectedStatus": 200 }
      ]
    },
    {
      "name": "CriticalService",
      "patterns": [
        { "type": "Process", "target": "winlogon" }
      ]
    }
  ]
}
```

---

## Running PatchPilot

### Non-Interactive Execution (RMM-Safe)

PatchPilot is designed for unattended execution. It never prompts for input.

**[evidence]** `Invoke-PatchPilotRun.ps1:9-11`
```
- Non-interactive / RMM-friendly: deterministic exit codes and no UI prompts.
- Evidence-first: final exit code is computed from persisted artifacts, not in-memory state.
```

### Basic Invocation

```powershell
# Import module
Import-Module 'C:\Program Files\PatchPilot\src\PatchPilot.Engine\PatchPilot.Engine.psd1'

# Run with explicit output root
$exitCode = Invoke-PatchPilotRun `
    -ConfigPath 'C:\PatchPilot\config.json' `
    -OutputRoot 'C:\PatchPilot\Output'

# Check result
Write-Host "Exit code: $exitCode"
```

### Multi-Tenant Invocation (MSP)

```powershell
$exitCode = Invoke-PatchPilotRun `
    -ConfigPath 'C:\PatchPilot\config.json' `
    -OutputRoot 'C:\PatchPilot\Output' `
    -TenantId 'MSP-001' `
    -ClientId 'ACME-Corp' `
    -SiteId 'HQ' `
    -DeviceId $env:COMPUTERNAME
```

### Test Mode (Dry-Run)

Test mode exercises the full pipeline without querying Windows Update or installing patches:

```powershell
$exitCode = Invoke-PatchPilotRun `
    -ConfigPath 'C:\PatchPilot\config.json' `
    -OutputRoot 'C:\PatchPilot\Test' `
    -TestMode
```

**[evidence]** `Invoke-PatchPilotRun.ps1:23-24`
```
-TestMode
    Forces a no-op, dependency-light run suitable for CI/pester
```

### RMM Command-Line Invocation

For RMM scripts, use validated quoting patterns:

```powershell
# Recommended: -File invocation (most reliable)
pwsh -NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\Run-PatchPilot.ps1"

# Alternative: -Command with proper quoting
pwsh -NoProfile -Command "& { Import-Module 'C:\Program Files\PatchPilot\src\PatchPilot.Engine\PatchPilot.Engine.psd1'; exit (Invoke-PatchPilotRun -ConfigPath 'C:\PatchPilot\config.json' -OutputRoot 'C:\PatchPilot\Output') }"
```

See [Local Execution & Validation](Local-Execution-and-Validation.md) for additional patterns.

---

## Reading Outputs & Reports

### Output Directory Structure

```
OutputRoot\
├── Runs\<RunId>\           # Per-run evidence
│   ├── artifact-index.json     # SHA-256 indexed artifacts
│   ├── manifest.json           # Merkle root integrity
│   ├── run.json                # Run metadata + exit code
│   ├── Logs\
│   │   ├── Events.jsonl        # Hash-chained event timeline
│   │   └── install-summary.jsonl
│   ├── Artifacts\
│   │   ├── Baseline\<RunId>\baseline.json
│   │   ├── Snapshot\<RunId>\snapshot.json
│   │   ├── UpdateCatalog\<RunId>\catalog.json
│   │   └── Diagnostics\LightDiag\<RunId>\
│   └── Reports\
│       ├── final-report.json
│       ├── final-report.html
│       ├── pre-validation.json
│       ├── post-validation.json
│       ├── regressions.json
│       └── diff-report.json
└── State\Tenants\<T>\Clients\<C>\Sites\<S>\Devices\<D>\
    ├── lock.json               # Concurrency guard
    └── reboot-required.json    # Resume cookie
```

### Quick Commands: Find Latest Run

```powershell
$OutputRoot = 'C:\PatchPilot\Output'
$LatestRun = Get-ChildItem -Path (Join-Path $OutputRoot 'Runs') -Directory |
    Sort-Object LastWriteTimeUtc -Descending |
    Select-Object -First 1

$RunRoot = $LatestRun.FullName
$RunId = $LatestRun.Name
Write-Host "Latest run: $RunId"
Write-Host "Run root: $RunRoot"
```

### Quick Commands: Check Exit Code

```powershell
$RunJson = Get-Content (Join-Path $RunRoot 'run.json') -Raw | ConvertFrom-Json
Write-Host "Exit code: $($RunJson.exitCode)"
Write-Host "Start: $($RunJson.startTimeUtc)"
Write-Host "End: $($RunJson.endTimeUtc)"
```

### Quick Commands: View Install Summary

```powershell
# Show all updates
Get-Content (Join-Path $RunRoot 'Logs\install-summary.jsonl') |
    ForEach-Object { $_ | ConvertFrom-Json } |
    Format-Table kb, title, installed, hresult, rebootRequired

# Show failed installs only
Get-Content (Join-Path $RunRoot 'Logs\install-summary.jsonl') |
    ForEach-Object { $_ | ConvertFrom-Json } |
    Where-Object { -not $_.installed } |
    Format-Table kb, title, hresult
```

### Quick Commands: View Regressions

```powershell
$Regressions = Get-Content (Join-Path $RunRoot 'Reports\regressions.json') -Raw | ConvertFrom-Json
Write-Host "Total regressions: $($Regressions.TotalRegressions)"
$Regressions.Regressions | Format-Table app, checkName, preStatus, postStatus
```

### Quick Commands: Open HTML Report

```powershell
$HtmlReport = Join-Path $RunRoot 'Reports\final-report.html'
if (Test-Path $HtmlReport) { Start-Process $HtmlReport }
```

---

## Exit Code Reference

| Code | Name | Meaning | Typical Action |
|------|------|---------|----------------|
| **0** | Success | All phases completed, no failures | Log and close ticket |
| **100** | PartialSuccess | Reserved (not currently emitted) | Review artifacts |
| **150** | RebootRequired | Reboot cookie active; resume after reboot | Schedule reboot, re-run |
| **170** | ConcurrencyLock | Another run is active on this device | Retry in 30 minutes |
| **210** | InstallFailure | One or more updates failed to install | Review install-summary.jsonl |
| **220** | ValidationFailure | Post-patch regressions detected | Review regressions.json |
| **230** | DiagnosticsFailure | Required diagnostics failed | Review diagnostics-summary.json |
| **240** | ReportingFailure | Critical error or Phase11 failed | Escalate; check Events.jsonl |

**[evidence]** `Get-PatchPilotExitCodes.ps1` defines these constants.

---

## Common Failure Scenarios & Remediation

### Scenario 1: Exit Code 150 (Reboot Required)

**Symptoms:**
- Run exits immediately with code 150
- No patches installed this run

**Cause:** A reboot cookie from a prior run exists.

**Diagnosis:**
```powershell
$DeviceState = 'C:\PatchPilot\Output\State\Tenants\T0\Clients\C0\Sites\S0\Devices\' + $env:COMPUTERNAME
$CookiePath = Join-Path $DeviceState 'reboot-required.json'
if (Test-Path $CookiePath) {
    Get-Content $CookiePath | ConvertFrom-Json
}
```

**Remediation:**
1. **Preferred:** Reboot the machine and re-run PatchPilot (it auto-resumes at Phase07)
2. **Manual clear (if machine was rebooted already):** Delete the cookie file:
   ```powershell
   Remove-Item $CookiePath -Force
   ```

### Scenario 2: Exit Code 170 (Concurrency Lock)

**Symptoms:**
- Run exits immediately with code 170
- Event log shows `ConcurrencyLockDetected`

**Cause:** Another PatchPilot run is active, or a stale lock exists.

**Diagnosis:**
```powershell
$DeviceState = 'C:\PatchPilot\Output\State\Tenants\T0\Clients\C0\Sites\S0\Devices\' + $env:COMPUTERNAME
$LockPath = Join-Path $DeviceState 'lock.json'
if (Test-Path $LockPath) {
    $Lock = Get-Content $LockPath | ConvertFrom-Json
    Write-Host "Lock acquired: $($Lock.acquiredUtc)"
    Write-Host "PID: $($Lock.pid)"
    Write-Host "Host: $($Lock.host)"

    # Check if process is still running
    $Process = Get-Process -Id $Lock.pid -ErrorAction SilentlyContinue
    if ($Process) { Write-Host "Process still running" }
    else { Write-Host "Process NOT running (stale lock)" }
}
```

**Remediation:**
1. **If process is running:** Wait for it to complete
2. **If stale lock:** PatchPilot auto-clears after `lockTtlMinutes` (default 120). To force:
   ```powershell
   Remove-Item $LockPath -Force
   ```

**[evidence]** `Invoke-PatchPilotRun.ps1:309-366` implements stale lock recovery.

### Scenario 3: Exit Code 210 (Install Failure)

**Symptoms:**
- Run completes but exit code is 210
- Some updates show `installed = false`

**Diagnosis:**
```powershell
$Failed = Get-Content (Join-Path $RunRoot 'Logs\install-summary.jsonl') |
    ForEach-Object { $_ | ConvertFrom-Json } |
    Where-Object { -not $_.installed }

$Failed | Format-Table kb, title, hresult

# Decode HRESULT
foreach ($F in $Failed) {
    $hex = '0x{0:X8}' -f $F.hresult
    Write-Host "$($F.kb): HRESULT $hex"
}
```

**Common HRESULT Codes:**
| HRESULT | Meaning | Action |
|---------|---------|--------|
| 0x80070005 | Access denied | Run as Administrator |
| 0x80240017 | Not applicable | KB already installed or N/A |
| 0x800F0922 | CBS session blocked | Pending reboot; reboot and retry |
| 0x80070002 | File not found | Download issue; retry |
| 0x80240016 | Reboot required before install | Reboot first |

**Remediation:**
1. Check Windows Update logs: `%windir%\Logs\CBS\CBS.log`
2. Reboot if required and retry
3. If persistent, exclude KB via `UpdatePolicy.json` excludedKBs

### Scenario 4: Exit Code 220 (Validation Failure / Regression)

**Symptoms:**
- Run completes but exit code is 220
- `regressions.json` shows TotalRegressions > 0

**Diagnosis:**
```powershell
$Reg = Get-Content (Join-Path $RunRoot 'Reports\regressions.json') -Raw | ConvertFrom-Json
Write-Host "Total regressions: $($Reg.TotalRegressions)"

foreach ($R in $Reg.Regressions) {
    Write-Host "App: $($R.app)"
    Write-Host "  Check: $($R.checkName)"
    Write-Host "  Pre-patch: $($R.preStatus)"
    Write-Host "  Post-patch: $($R.postStatus)"
    Write-Host ""
}
```

**Remediation:**
1. **If false positive:** Update `AppValidationPolicy.json` to adjust check
2. **If real regression:** Investigate application logs; consider rollback
3. **If transient:** Application may have been restarting; re-run validation

### Scenario 5: Exit Code 230 (Diagnostics Failure)

**Symptoms:**
- Run fails with exit code 230
- Only occurs if `diagnostics.required = true`

**Diagnosis:**
```powershell
$DiagSummary = Join-Path $RunRoot "Artifacts\Diagnostics\LightDiag\$RunId\diagnostics-summary.json"
$Diag = Get-Content $DiagSummary -Raw | ConvertFrom-Json
Write-Host "Status: $($Diag.status)"
Write-Host "Triggered by: $($Diag.triggeredBy)"
$Diag.collectors | Format-Table name, status, artifacts, bytes
```

**Remediation:**
1. Check collector failures in diagnostics-summary.json
2. If non-critical, set `diagnostics.required = false` in config
3. Review collector permissions (event log access, file access)

### Scenario 6: Exit Code 240 (Critical/Reporting Failure)

**Symptoms:**
- Run terminates with exit code 240
- `final-report.json` may be missing or incomplete

**Diagnosis:**
```powershell
# Check for exception in Events.jsonl
$Events = Get-Content (Join-Path $RunRoot 'Logs\Events.jsonl') |
    ForEach-Object { $_ | ConvertFrom-Json }

$Events | Where-Object { $_.level -eq 'Error' } | Select-Object timestamp, event, data
```

**Remediation:**
1. Review `Events.jsonl` for `RunException` events
2. Check disk space (artifacts require storage)
3. Verify module files are complete (corruption check)
4. Escalate if unresolved

---

## Safety Controls

### Maintenance Window Awareness

PatchPilot can detect maintenance windows via RMM integration. See [RMM Integration](RMM-Integration.md) for:
- `UpdatePolicy.maintenanceWindow` settings
- RMM-specific maintenance window detection

### Reboot Handling

**[evidence]** `Invoke-PatchPilotRun.ps1:429-437`

PatchPilot NEVER auto-reboots. Instead:
1. Phase06 checks if reboot is required
2. If needed, writes a reboot cookie
3. Returns exit code 150
4. RMM schedules reboot externally
5. On next run, PatchPilot resumes at Phase07

**Reboot Cookie Location:**
```
OutputRoot\State\Tenants\<T>\Clients\<C>\Sites\<S>\Devices\<D>\reboot-required.json
```

### Simulate Mode (Safety Default)

**[evidence]** `Invoke-PatchPilotRun.ps1:382-421`

By default, installs are simulated unless explicitly enabled:
- Set `patchInstall.simulateInstall = false` in config, OR
- Set `updateSettings.installMode = "live"` in UpdatePolicy.json

---

## Evidence Packaging for Tickets & Audits

### Package Evidence for a Ticket

```powershell
$RunRoot = 'C:\PatchPilot\Output\Runs\abc123-...'
$TicketId = 'INC0012345'
$PackagePath = "C:\Temp\PatchPilot-$TicketId.zip"

# Create evidence package
$FilesToInclude = @(
    (Join-Path $RunRoot 'run.json'),
    (Join-Path $RunRoot 'manifest.json'),
    (Join-Path $RunRoot 'Reports\final-report.json'),
    (Join-Path $RunRoot 'Reports\final-report.html'),
    (Join-Path $RunRoot 'Reports\regressions.json'),
    (Join-Path $RunRoot 'Logs\install-summary.jsonl'),
    (Join-Path $RunRoot 'Logs\Events.jsonl')
)

Compress-Archive -Path $FilesToInclude -DestinationPath $PackagePath
Write-Host "Evidence packaged: $PackagePath"
```

### Package for Compliance Audit

```powershell
$RunRoot = 'C:\PatchPilot\Output\Runs\abc123-...'
$AuditPath = "C:\Temp\PatchPilot-Audit-$(Get-Date -Format 'yyyyMMdd').zip"

# Full audit package with integrity proof
Compress-Archive -Path $RunRoot -DestinationPath $AuditPath
Write-Host "Audit package: $AuditPath"
Write-Host "Include manifest.json for Merkle root verification"
```

### Verify Evidence Integrity

```powershell
# Verify hash chain in Events.jsonl
$EventsPath = Join-Path $RunRoot 'Logs\Events.jsonl'
$Lines = Get-Content $EventsPath
$Sha256 = [System.Security.Cryptography.SHA256]::Create()

$ChainValid = $true
for ($i = 1; $i -lt $Lines.Count; $i++) {
    $PrevHash = [BitConverter]::ToString(
        $Sha256.ComputeHash([Text.Encoding]::UTF8.GetBytes($Lines[$i-1]))
    ).Replace('-','').ToLower()

    $Current = $Lines[$i] | ConvertFrom-Json
    if ($Current.prevHash -ne $PrevHash) {
        Write-Warning "Chain broken at line $i"
        $ChainValid = $false
        break
    }
}

if ($ChainValid) { Write-Host "Event chain verified" }
```

---

## Quick Reference Commands

### Module Commands

```powershell
# Import module
Import-Module 'C:\Program Files\PatchPilot\src\PatchPilot.Engine\PatchPilot.Engine.psd1'

# Get version
Get-PatchPilotVersion

# Get exit codes
Get-PatchPilotExitCodes

# Re-evaluate exit code from evidence
Get-PatchPilotExitCodeFromEvidence -RunRoot $RunRoot
```

### Diagnostic Commands

```powershell
# Find latest run
$Latest = Get-ChildItem 'C:\PatchPilot\Output\Runs' -Directory | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1

# Check run status
(Get-Content (Join-Path $Latest.FullName 'run.json') | ConvertFrom-Json).exitCode

# View recent events
Get-Content (Join-Path $Latest.FullName 'Logs\Events.jsonl') | Select-Object -Last 10 | ForEach-Object { ($_ | ConvertFrom-Json) | Select-Object timestamp, event, level }

# Check for active lock
$Lock = 'C:\PatchPilot\Output\State\Tenants\T0\Clients\C0\Sites\S0\Devices\' + $env:COMPUTERNAME + '\lock.json'
if (Test-Path $Lock) { Get-Content $Lock | ConvertFrom-Json }

# Check for reboot cookie
$Cookie = 'C:\PatchPilot\Output\State\Tenants\T0\Clients\C0\Sites\S0\Devices\' + $env:COMPUTERNAME + '\reboot-required.json'
if (Test-Path $Cookie) { Get-Content $Cookie | ConvertFrom-Json }
```

### Cleanup Commands

```powershell
# Remove runs older than 90 days
$Threshold = (Get-Date).AddDays(-90)
Get-ChildItem 'C:\PatchPilot\Output\Runs' -Directory |
    Where-Object { $_.LastWriteTimeUtc -lt $Threshold } |
    Remove-Item -Recurse -Force

# Clear stale lock (use with caution)
Remove-Item 'C:\PatchPilot\Output\State\Tenants\T0\Clients\C0\Sites\S0\Devices\HOSTNAME\lock.json' -Force

# Clear reboot cookie (use with caution - only if machine was already rebooted)
Remove-Item 'C:\PatchPilot\Output\State\Tenants\T0\Clients\C0\Sites\S0\Devices\HOSTNAME\reboot-required.json' -Force
```

---

## Escalation Path

| Situation | First Response | Escalate To |
|-----------|---------------|-------------|
| Exit code 150 persists after reboot | Clear cookie manually | Level 2 |
| Exit code 170 with no active process | Clear stale lock | Level 2 |
| Exit code 210 (install failure) | Check HRESULT, retry | Level 2 if persistent |
| Exit code 220 (regression) | Review regressions.json | App owner / Level 3 |
| Exit code 230 (diagnostics required) | Check diagnostics config | Level 2 |
| Exit code 240 (critical) | Package evidence, escalate | Level 3 immediately |
| Module won't import | Check PS7, unblock files | Level 2 |
| Execution policy errors | Set Bypass for session | Level 2 |

---

## See Also

- [User Guide](User-Guide.md) - General usage overview
- [Troubleshooting](Troubleshooting.md) - Detailed troubleshooting procedures
- [RMM Integration](RMM-Integration.md) - RMM-specific deployment
- [Exit Codes Reference](../API/Exit-Codes.md) - Complete exit code documentation
- [Evidence Verification](Evidence-Verification.md) - Integrity verification procedures
- [Security Model](../SECURITY-COMPLIANCE/Security-Model-and-Redaction.md) - Security architecture
- [Data Retention](../SECURITY-COMPLIANCE/Data-Retention.md) - Retention policies and cleanup
