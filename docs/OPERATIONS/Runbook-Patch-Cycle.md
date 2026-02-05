# PatchPilot Patch Cycle Runbook

## Purpose

Step-by-step operational procedures for executing a patch cycle using PatchPilot.Engine.

**Referenced artifacts:**
- Phase functions: `src/PatchPilot.Engine/Private/Invoke-Phase*.ps1`
- Test files: `tests/Stage*.Tests.ps1`

## Pre-Flight Checklist

- [ ] PowerShell 7 installed
- [ ] PatchPilot module deployed
- [ ] Policies configured (`examples/configs/`)
- [ ] RMM monitoring configured
- [ ] Change control approved
- [ ] Maintenance window scheduled
- [ ] Backup verified

## Execution Steps

### 1. Pre-Flight Validation

```powershell
# Verify module
Get-Module -ListAvailable PatchPilot.Engine

# Check policies
Test-Path "C:\PatchPilot\examples\configs\UpdatePolicy.json"

# Verify admin rights
([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
```

### 2. Initiate Patch Run

```powershell
$outputRoot = "C:\PatchPilot\Output\$(Get-Date -Format 'yyyy-MM-dd-HHmm')"

$exitCode = Invoke-PatchPilotRun `
    -OutputRoot $outputRoot `
    -TenantId "MSP-001" `
    -ClientId "ClientABC" `
    -DeviceId $env:COMPUTERNAME

Write-Output "Exit Code: $exitCode"
```

### 3. Monitor Progress

```powershell
# Watch events log
Get-Content "$outputRoot\Logs\Events.jsonl" -Wait | ForEach-Object {
    $event = $_ | ConvertFrom-Json
    Write-Output "[$($event.level)] $($event.event) - Phase: $($event.phaseId)"
}
```

### 4. Phase-by-Phase Execution

#### Phase01: Initialization
- Load configs, merge policies
- Validate PS7, check admin rights
- Create output structure
- **Evidence:** `State/state.json` with initial checkpoint

#### Phase02: Baseline Snapshot
- Capture pre-patch system state
- **Evidence:** `Artifacts/Baseline/<RunId>/baseline.json`
- **Raw proofs:** `Artifacts/Baseline/<RunId>/raw/*`

#### Phase03: Update Catalog Fetch
- Query Windows Update via COM/WaaS
- **Evidence:** `Artifacts/UpdateCatalog/<RunId>/catalog.json`

#### Phase04: Pre-Backup & Pre-Validation
- Run application health checks
- **Evidence:** `Reports/<RunId>/pre-validation.json`

#### Phase05: Patch Install
- Install updates per policy
- **Evidence:** `Logs/install-summary.jsonl` (one line per update)
- **Exit codes:** 210 if failures, 150 if reboot required

#### Phase06: Reboot Orchestration
- Persist state before reboot
- **Evidence:** `State/RebootPlan.json`

#### Phase07: Post-Snapshot
- Capture post-patch state (parity with Phase02)
- **Evidence:** `Artifacts/Snapshot/<RunId>/snapshot.json`

#### Phase08: Post-Validation
- Re-run app validation patterns
- **Evidence:** `Reports/<RunId>/post-validation.json`
- **Regressions:** `Reports/<RunId>/regressions.json`

#### Phase09: Diagnostics/LightDiag
- Run Microsoft LightDiag collectors if failures detected
- **Evidence:** `Artifacts/Diagnostics/LightDiag/<RunId>/diagnostics-summary.json`
- **Caps:** MaxSizeMB, MaxMinutes enforced

#### Phase10: Evidence Indexing
- Hash all artifacts (SHA-256)
- Build Merkle root
- **Evidence:** `artifact-index.json`, `manifest.json`

#### Phase11: Reporting
- Generate final reports from persisted evidence only
- **Evidence:** `Reports/<RunId>/final-report.json`, `final-report.html`
- **Standards mapping:** NIST 800-40r4, 800-53r5, CIS v8

### 5. Post-Execution Verification

```powershell
# Check exit code
switch ($exitCode) {
    0   { "SUCCESS" }
    100 { "PARTIAL SUCCESS - Review logs" }
    150 { "REBOOT REQUIRED" }
    210 { "INSTALL FAILURE" }
    220 { "VALIDATION FAILURE" }
    default { "UNEXPECTED: $exitCode" }
}

# Verify evidence integrity
Get-PatchPilotExitCodeFromEvidence -OutputRoot $outputRoot

# Review final report
$report = Get-Content "$outputRoot\Reports\*\final-report.json" | ConvertFrom-Json
$report | Format-List RunId, ExitCode, PatchesInstalled, RebootRequired
```

### 6. If Reboot Required

```powershell
# Schedule restart
if ($exitCode -eq 150) {
    Restart-Computer -Force -Delay 300  # 5 min delay
}

# After reboot, resume automatically
Invoke-PatchPilotRun -OutputRoot $outputRoot
# Engine detects RebootPlan.json and resumes at Phase07
```

## Troubleshooting During Execution

### Concurrency Lock (170)

```powershell
# Check for stale lock
Get-Content "$outputRoot\State\lock.json" | ConvertFrom-Json

# Remove if stale
Remove-Item "$outputRoot\State\lock.json" -Force
```

### Install Failures (210)

```powershell
# Check which updates failed
Get-Content "$outputRoot\Logs\install-summary.jsonl" | ConvertFrom-Json | 
    Where installed -eq $false | 
    Format-Table kb, title, hresult
```

### Validation Failures (220)

```powershell
# Check regressions
$regressions = Get-Content "$outputRoot\Reports\*\regressions.json" | ConvertFrom-Json
$regressions | Format-Table App, Pattern, PreStatus, PostStatus, Confidence
```

## Post-Cycle Activities

1. **Archive Evidence:**
```powershell
$archivePath = "\server\PatchPilot\Archives\$(Get-Date -Format 'yyyy-MM')"
Copy-Item -Path $outputRoot -Destination $archivePath -Recurse
```

2. **Update Change Control:**
- Attach `final-report.html`
- Reference manifest.merkleRoot for evidence integrity

3. **RMM Alert Resolution:**
- Clear maintenance mode
- Update asset inventory
- Document any regressions

## See Also

- [User Guide](./User-Guide.md)
- [Troubleshooting](./Troubleshooting.md)
- [Evidence Verification](./Evidence-Verification.md)
- [ITSM Change Control](./ITSM-ChangeControl.md)
