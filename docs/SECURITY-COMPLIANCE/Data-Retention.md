# Data Retention

## Overview

PatchPilot generates evidence artifacts for audit, compliance, and troubleshooting purposes. This document defines retention policies, storage locations, lifecycle management, and cleanup procedures for all artifact classes.

**Referenced Code:**
- Run folder creation: `src/PatchPilot.Engine/Public/Invoke-PatchPilotRun.ps1:266-271`
- Per-device state: `src/PatchPilot.Engine/Public/Invoke-PatchPilotRun.ps1:239`
- Diagnostics history: `src/PatchPilot.Engine/Private/Invoke-Phase09.ps1:541-543`
- Reboot cookie lifecycle: `src/PatchPilot.Engine/Public/Invoke-PatchPilotRun.ps1:258-265`

---

## Storage Hierarchy

### OutputRoot Structure

PatchPilot creates all artifacts under the `OutputRoot` directory:

```
OutputRoot\
├── Runs\
│   └── <RunId>\              # Per-run evidence (GUID-named)
│       ├── artifact-index.json
│       ├── manifest.json
│       ├── run.json
│       ├── Logs\
│       │   ├── Events.jsonl
│       │   └── install-summary.jsonl
│       ├── Artifacts\
│       │   ├── Baseline\<RunId>\
│       │   ├── Snapshot\<RunId>\
│       │   ├── UpdateCatalog\<RunId>\
│       │   └── Diagnostics\LightDiag\<RunId>\
│       ├── Reports\
│       │   ├── pre-validation.json
│       │   ├── post-validation.json
│       │   ├── regressions.json
│       │   ├── diff-report.json
│       │   ├── final-report.json
│       │   ├── final-report.html
│       │   └── redaction-log.json
│       ├── Telemetry\
│       └── State\
│           └── state.json
└── State\
    └── Tenants\<TenantId>\Clients\<ClientId>\Sites\<SiteId>\Devices\<DeviceId>\
        ├── lock.json                       # Concurrency guard
        ├── reboot-required.json            # Resume cookie
        ├── reboot-required.consumed.*.json # Archived cookies
        └── diagnostics-run-history.json    # Throttling history
```

### Default OutputRoot Locations

**[evidence]** `src/PatchPilot.ps1:122-150`

If not explicitly specified, PatchPilot resolves OutputRoot in this order:
1. `-OutputRoot` parameter (explicit)
2. `config.outputRoot` from configuration file
3. `$env:LOCALAPPDATA\PatchPilot` (if LOCALAPPDATA exists)
4. `$env:ProgramData\PatchPilot` (fallback)
5. `$env:TEMP\PatchPilot` (last resort)

---

## Data Classes and Retention

### Retention Matrix

| Data Class | Location | Recommended Retention | Compliance Driver |
|------------|----------|----------------------|-------------------|
| Run Evidence | `Runs\<RunId>\` | 90-365 days | Audit trail |
| Manifest/Index | `Runs\<RunId>\manifest.json` | Same as run | Integrity proof |
| Install Summary | `Runs\<RunId>\Logs\install-summary.jsonl` | Same as run | Patch compliance |
| Validation Reports | `Runs\<RunId>\Reports\*.json` | Same as run | Regression proof |
| Diagnostics | `Runs\<RunId>\Artifacts\Diagnostics\` | 30-90 days | Troubleshooting |
| Event Logs (.evtx) | `Runs\<RunId>\Artifacts\Diagnostics\LightDiag\*\EventLogs\` | 30-60 days | Troubleshooting |
| Per-Device State | `State\Tenants\...\Devices\...\` | Active only | Operational |
| Diagnostics History | `*\diagnostics-run-history.json` | 50 entries | Throttling |
| Consumed Cookies | `*\reboot-required.consumed.*.json` | 7-30 days | Audit trail |

### Compliance-Driven Minimums

| Standard | Artifact | Minimum Retention |
|----------|----------|-------------------|
| NIST 800-53r5 AU-11 | All audit records | 3 years (varies by org) |
| CIS Controls v8 | Vulnerability management evidence | 1 year |
| SOC 2 | System change evidence | Duration of audit period |
| HIPAA | Patch evidence | 6 years |
| PCI-DSS | System activity logs | 1 year |

**Note:** Consult your compliance officer for organization-specific requirements.

---

## Artifact Lifecycle

### Run Folder Lifecycle

1. **Creation**: `Invoke-PatchPilotRun` creates `Runs\<RunId>\` with a GUID-based name
2. **Population**: Phases 01-11 write artifacts progressively
3. **Finalization**: Phase10 computes hashes; Phase11 writes final reports
4. **Archival**: Operator archives per retention policy
5. **Deletion**: Operator deletes after retention period expires

### Per-Device State Lifecycle

#### Concurrency Lock (`lock.json`)

**[evidence]** `Invoke-PatchPilotRun.ps1:298-367`

- **Created**: At run start (atomic file creation)
- **Contents**: lockId, acquiredUtc, runId, pid, host
- **Deleted**: In `finally` block on normal/error completion
- **Stale Recovery**: Auto-removed if TTL exceeded and PID not alive

```json
{
  "schemaVersion": "1.0",
  "lockId": "a1b2c3d4-...",
  "acquiredUtc": "2026-01-23T10:00:00Z",
  "runId": "abc123-...",
  "pid": 1234,
  "host": "WIN-SERVER01"
}
```

**TTL Configuration:**
```json
{
  "lockTtlMinutes": 120
}
```

#### Reboot Cookie (`reboot-required.json`)

**[evidence]** `Invoke-PatchPilotRun.ps1:242-265`

- **Created**: Phase06 when reboot is required
- **Consumed**: On resume, moved to `reboot-required.consumed.<timestamp>.json`
- **Contents**: runRoot, runId, timestamp

```json
{
  "runRoot": "C:\\PatchPilot\\Output\\Runs\\abc123-...",
  "runId": "abc123-...",
  "timestamp": "2026-01-23T10:05:00Z"
}
```

**Consumed Cookie Example:**
```
reboot-required.consumed.20260123T100600Z.json
```

#### Diagnostics History (`diagnostics-run-history.json`)

**[evidence]** `Invoke-Phase09.ps1:534-544`

- **Location**: Per-device state root (preferred) or run state folder
- **Contents**: Array of diagnostic run records
- **Bounded**: Keeps last 50 entries automatically

```powershell
# From Invoke-Phase09.ps1:541-543
if ($HistoryArray.Count -gt 50) {
    $HistoryArray = $HistoryArray | Select-Object -Last 50
}
```

**Example Entry:**
```json
{
  "timestampUtc": "2026-01-23T10:08:00Z",
  "deviceId": "WIN-SERVER01",
  "profile": "LightDiag",
  "triggeredBy": ["InstallFailure"],
  "status": "Success",
  "totalBytes": 1048576,
  "artifactCount": 4,
  "durationMs": 12345,
  "capExceeded": false
}
```

---

## Cleanup Automation

### PowerShell Cleanup Scripts

#### Remove Runs Older Than N Days

```powershell
# Remove run folders older than 90 days
$OutputRoot = 'C:\PatchPilot\Output'
$RetentionDays = 90
$Cutoff = (Get-Date).AddDays(-$RetentionDays)

Get-ChildItem -Path (Join-Path $OutputRoot 'Runs') -Directory |
    Where-Object { $_.LastWriteTime -lt $Cutoff } |
    ForEach-Object {
        Write-Output "Removing: $($_.FullName)"
        Remove-Item -Path $_.FullName -Recurse -Force
    }
```

#### Remove Consumed Reboot Cookies

```powershell
# Remove consumed cookies older than 7 days
$OutputRoot = 'C:\PatchPilot\Output'
$RetentionDays = 7
$Cutoff = (Get-Date).AddDays(-$RetentionDays)

Get-ChildItem -Path (Join-Path $OutputRoot 'State') -Recurse -Filter 'reboot-required.consumed.*.json' |
    Where-Object { $_.LastWriteTime -lt $Cutoff } |
    ForEach-Object {
        Write-Output "Removing: $($_.FullName)"
        Remove-Item -Path $_.FullName -Force
    }
```

#### Remove Stale Locks

```powershell
# Remove locks older than 4 hours where PID is not alive
$OutputRoot = 'C:\PatchPilot\Output'
$MaxAgeHours = 4

Get-ChildItem -Path (Join-Path $OutputRoot 'State') -Recurse -Filter 'lock.json' |
    ForEach-Object {
        $Lock = Get-Content $_.FullName -Raw | ConvertFrom-Json
        $AcquiredUtc = [datetime]::Parse($Lock.acquiredUtc).ToUniversalTime()
        $AgeHours = ((Get-Date).ToUniversalTime() - $AcquiredUtc).TotalHours

        if ($AgeHours -gt $MaxAgeHours) {
            $PidAlive = $null -ne (Get-Process -Id $Lock.pid -ErrorAction SilentlyContinue)
            if (-not $PidAlive) {
                Write-Output "Removing stale lock: $($_.FullName)"
                Remove-Item -Path $_.FullName -Force
            }
        }
    }
```

### Scheduled Task Example

Create a scheduled task for automated cleanup:

```powershell
$Action = New-ScheduledTaskAction -Execute 'pwsh.exe' -Argument @'
-NoProfile -NonInteractive -Command "& {
    $OutputRoot = 'C:\PatchPilot\Output'
    $RetentionDays = 90

    # Remove old runs
    Get-ChildItem (Join-Path $OutputRoot 'Runs') -Directory |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$RetentionDays) } |
        Remove-Item -Recurse -Force

    # Remove old consumed cookies
    Get-ChildItem (Join-Path $OutputRoot 'State') -Recurse -Filter 'reboot-required.consumed.*.json' |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } |
        Remove-Item -Force
}"
'@

$Trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 03:00
$Principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest

Register-ScheduledTask -TaskName 'PatchPilot-Cleanup' -Action $Action -Trigger $Trigger -Principal $Principal
```

---

## Archival Strategies

### Before Deletion: Archive Evidence

For compliance-sensitive environments, archive evidence before deletion:

```powershell
# Archive a run folder before deletion
$RunId = 'abc123-def456-...'
$RunRoot = Join-Path 'C:\PatchPilot\Output\Runs' $RunId
$ArchivePath = "\\archive-server\PatchPilot\Archives\$RunId.zip"

# Verify integrity before archiving
$Manifest = Get-Content (Join-Path $RunRoot 'manifest.json') -Raw | ConvertFrom-Json
Write-Output "Archiving RunId: $RunId (Merkle Root: $($Manifest.merkleRoot))"

Compress-Archive -Path $RunRoot -DestinationPath $ArchivePath -CompressionLevel Optimal

# Log archive action
@{
    action = 'Archive'
    runId = $RunId
    merkleRoot = $Manifest.merkleRoot
    archivedTo = $ArchivePath
    timestamp = (Get-Date).ToUniversalTime().ToString('o')
} | ConvertTo-Json | Add-Content -Path '\\archive-server\PatchPilot\archive-log.jsonl'
```

### Archive Index

Maintain an archive index for quick lookup:

```json
{
  "runId": "abc123-...",
  "tenantId": "MSP001",
  "clientId": "ACME",
  "deviceId": "WIN-SERVER01",
  "archiveDate": "2026-04-23T03:00:00Z",
  "archivePath": "\\\\archive-server\\PatchPilot\\Archives\\abc123-....zip",
  "merkleRoot": "f7c3bc1d808e04732adf679965ccc34ca7ae3441...",
  "eventsChainHead": "a3c9f12e8b5d3c1a2e4f6b7c8d9e0f1a2b3c4d5e6...",
  "originalRunDate": "2026-01-23T10:00:00Z"
}
```

---

## Storage Estimation

### Per-Run Size Estimates

| Component | Typical Size | Notes |
|-----------|-------------|-------|
| Events.jsonl | 50-200 KB | Grows with phase complexity |
| install-summary.jsonl | 1-10 KB | ~200 bytes per update |
| baseline.json | 100-500 KB | Depends on installed apps |
| snapshot.json | 100-500 KB | Same as baseline |
| catalog.json | 10-100 KB | Depends on available updates |
| validation reports | 10-50 KB | Per-app validation |
| regressions.json | 1-10 KB | Usually small |
| diff-report.json | 5-50 KB | Depends on changes |
| final-report.json | 10-50 KB | Summary only |
| final-report.html | 20-100 KB | Includes styling |
| Diagnostics (Phase09) | 0-50 MB | Highly variable; cap-controlled |
| **Total (typical)** | **500 KB - 5 MB** | Without diagnostics |
| **Total (with diagnostics)** | **5 - 55 MB** | Cap defaults to 200 MB max |

### Fleet Storage Planning

| Devices | Runs/Month | Retention | Storage (no diag) | Storage (with diag) |
|---------|------------|-----------|-------------------|---------------------|
| 100 | 400 | 90 days | ~18 GB | ~90 GB |
| 500 | 2,000 | 90 days | ~90 GB | ~450 GB |
| 1,000 | 4,000 | 90 days | ~180 GB | ~900 GB |

**Recommendation:** Enable diagnostics in `OnFailure` mode (default) to minimize storage while retaining troubleshooting capability.

---

## Compliance Considerations

### Evidence Preservation for Legal Hold

If a legal hold is required:

1. **Identify affected runs** by tenant/client/device/date range
2. **Copy to immutable storage** (WORM, Azure Blob Immutable, AWS S3 Object Lock)
3. **Preserve manifest.json** for integrity verification
4. **Document chain of custody**

### Audit Trail for Deletions

Log all deletion actions:

```powershell
# Deletion audit log
$DeletionLog = @{
    action = 'Delete'
    runId = $RunId
    path = $RunRoot
    deletedBy = $env:USERNAME
    timestamp = (Get-Date).ToUniversalTime().ToString('o')
    reason = 'Retention policy (90 days)'
}

$DeletionLog | ConvertTo-Json | Add-Content -Path 'C:\PatchPilot\Output\deletion-log.jsonl'
```

---

## Troubleshooting Retention Issues

### Disk Space Alerts

Monitor OutputRoot for space issues:

```powershell
$OutputRoot = 'C:\PatchPilot\Output'
$Drive = (Get-Item $OutputRoot).PSDrive.Name
$FreeSpaceGB = (Get-PSDrive $Drive).Free / 1GB

if ($FreeSpaceGB -lt 10) {
    Write-Warning "Low disk space on $Drive`: $([math]::Round($FreeSpaceGB, 2)) GB free"
    # Trigger cleanup or alert
}
```

### Stale Run Folders

If run folders are not being cleaned:

1. Verify scheduled task is running
2. Check NTFS permissions on OutputRoot
3. Review cleanup script logs
4. Manually run cleanup with `-WhatIf` first

### Orphaned State Files

State files may become orphaned if runs are manually deleted:

```powershell
# Find state directories without corresponding runs
$StateRoot = Join-Path 'C:\PatchPilot\Output' 'State'
$RunsRoot = Join-Path 'C:\PatchPilot\Output' 'Runs'

$ValidRunIds = Get-ChildItem $RunsRoot -Directory | ForEach-Object { $_.Name }

Get-ChildItem $StateRoot -Recurse -Filter 'diagnostics-run-history.json' |
    ForEach-Object {
        $History = Get-Content $_.FullName -Raw | ConvertFrom-Json
        # Check if referenced runs exist
    }
```

---

## See Also

- [Security Model & Redaction](Security-Model-and-Redaction.md) - Data sensitivity classification
- [Artifacts & Schemas](../API/Artifacts-and-Schemas.md) - Complete artifact reference
- [Directory Layout](../APPENDICES/Directory-Layout.md) - Full directory structure
- [Compliance Mapping](Compliance-Mapping.md) - Retention requirements by standard
- [Troubleshooting](../OPERATIONS/Troubleshooting.md) - Operational issues
