# Output Artifact Reference

## Overview

This document provides a comprehensive reference for all artifacts produced by PatchPilot runs. It covers the directory structure, artifact naming conventions, schema mappings, exit code interpretation, and evidence integrity mechanisms.

**Referenced Code:**
- Artifact indexing: `src/PatchPilot.Engine/Private/New-ArtifactIndex.ps1`
- Manifest generation: `src/PatchPilot.Engine/Private/Write-Manifest.ps1`
- Final report: `src/PatchPilot.Engine/Private/Invoke-Phase11.ps1`
- Exit code computation: `src/PatchPilot.Engine/Public/Get-PatchPilotExitCodeFromEvidence.ps1`

---

## Directory Structure Overview

### OutputRoot Layout

```
OutputRoot\
├── Runs\                                    # Per-run evidence folders
│   └── <RunId>\                             # GUID-based run identifier
│       ├── artifact-index.json              # SHA-256 indexed artifacts
│       ├── manifest.json                    # Merkle root + chain head
│       ├── run.json                         # Run metadata + exit code
│       │
│       ├── Logs\
│       │   ├── Events.jsonl                 # Hash-chained event timeline
│       │   ├── install-summary.jsonl        # Per-update outcomes
│       │   └── Pipeline.log                 # Verbose pipeline log (if enabled)
│       │
│       ├── Artifacts\
│       │   ├── Baseline\<RunId>\
│       │   │   ├── baseline.json            # Pre-patch system snapshot
│       │   │   └── raw\                     # Raw command outputs
│       │   ├── Snapshot\<RunId>\
│       │   │   ├── snapshot.json            # Post-patch system snapshot
│       │   │   └── raw\
│       │   ├── UpdateCatalog\<RunId>\
│       │   │   └── catalog.json             # Windows Update metadata
│       │   ├── Validation\<RunId>\
│       │   │   ├── pre\                     # Pre-validation evidence
│       │   │   └── post\                    # Post-validation evidence
│       │   └── Diagnostics\LightDiag\<RunId>\
│       │       ├── diagnostics-summary.json
│       │       ├── EventLogs\               # Exported .evtx files
│       │       └── Files\                   # Collected system files
│       │
│       ├── Reports\
│       │   ├── pre-validation.json          # Phase04 validation results
│       │   ├── post-validation.json         # Phase08 validation results
│       │   ├── regressions.json             # Phase08 regression comparison
│       │   ├── diff-report.json             # Baseline vs snapshot diff
│       │   ├── final-report.json            # Phase11 comprehensive report
│       │   ├── final-report.html            # Human-readable HTML report
│       │   └── redaction-log.json           # What fields were redacted
│       │
│       ├── Telemetry\                       # (If telemetry enabled)
│       │   ├── spans.jsonl                  # OpenTelemetry-style spans
│       │   └── metrics.jsonl                # Performance metrics
│       │
│       └── State\
│           ├── state.json                   # Phase checkpoint data
│           └── RebootPlan.json              # Reboot orchestration
│
└── State\                                   # Per-device persistent state
    └── Tenants\<TenantId>\
        └── Clients\<ClientId>\
            └── Sites\<SiteId>\
                └── Devices\<DeviceId>\
                    ├── lock.json                    # Concurrency guard
                    ├── reboot-required.json         # Resume cookie
                    ├── reboot-required.consumed.*.json  # Consumed cookies (audit)
                    └── diagnostics-run-history.json # Throttling state
```

---

## RunId Naming Convention

**Format:** `<GUID>`
**Example:** `f47ac10b-58cc-4372-a567-0e02b2c3d479`

**[evidence]** `Invoke-PatchPilotRun.ps1:267`
```powershell
$RunId = ([guid]::NewGuid()).ToString()
```

The RunId is:
- Generated at run start (or inherited from reboot cookie for resume)
- Used as a subdirectory under `Runs\`
- Embedded in all artifacts for traceability
- Referenced in per-device state (reboot cookies, locks)

---

## Artifact Categories

### Category: Logs

| Artifact | Format | Schema | Purpose |
|----------|--------|--------|---------|
| `Events.jsonl` | JSONL | `events.schema.json` | Hash-chained event timeline |
| `install-summary.jsonl` | JSONL | `install-summary.schema.json` | Per-update install outcomes |
| `Pipeline.log` | Text | N/A | Verbose debug log (optional) |

**[evidence]** `New-ArtifactIndex.ps1:26-41` indexes Logs category.

### Category: Baseline

| Artifact | Format | Schema | Purpose |
|----------|--------|--------|---------|
| `baseline.json` | JSON | `baseline.schema.json` | Pre-patch system snapshot |
| `raw\*` | Various | N/A | Raw command outputs (services, drivers, apps) |

**Location:** `Artifacts\Baseline\<RunId>\`

### Category: Snapshot

| Artifact | Format | Schema | Purpose |
|----------|--------|--------|---------|
| `snapshot.json` | JSON | `snapshot.schema.json` | Post-patch system snapshot |
| `raw\*` | Various | N/A | Raw command outputs |

**Location:** `Artifacts\Snapshot\<RunId>\`

### Category: UpdateCatalog

| Artifact | Format | Schema | Purpose |
|----------|--------|--------|---------|
| `catalog.json` | JSON | N/A | Windows Update metadata (available updates) |

**Location:** `Artifacts\UpdateCatalog\<RunId>\`

### Category: Validation

| Artifact | Format | Schema | Purpose |
|----------|--------|--------|---------|
| `pre\*.json` | JSON | N/A | Per-check pre-validation evidence |
| `post\*.json` | JSON | N/A | Per-check post-validation evidence |

**Location:** `Artifacts\Validation\<RunId>\`

### Category: Diagnostics/LightDiag

| Artifact | Format | Schema | Purpose |
|----------|--------|--------|---------|
| `diagnostics-summary.json` | JSON | `diagnostics-summary.schema.json` | Collection summary |
| `EventLogs\*.evtx` | EVTX | N/A | Exported Windows event logs |
| `Files\*` | Various | N/A | Collected system files (CBS.log, etc.) |

**Location:** `Artifacts\Diagnostics\LightDiag\<RunId>\`

**[evidence]** `New-ArtifactIndex.ps1:94-109` indexes Diagnostics/LightDiag category.

### Category: Reports

| Artifact | Format | Schema | Purpose |
|----------|--------|--------|---------|
| `pre-validation.json` | JSON | `validation-result.schema.json` | Phase04 results |
| `post-validation.json` | JSON | `validation-result.schema.json` | Phase08 results |
| `regressions.json` | JSON | `regressions.schema.json` | Pre/post comparison |
| `diff-report.json` | JSON | `diff-report.schema.json` | Baseline vs snapshot diff |
| `final-report.json` | JSON | `final-report.schema.json` | Comprehensive summary |
| `final-report.html` | HTML | N/A | Human-readable report |
| `redaction-log.json` | JSON | N/A | Redaction audit trail |

**Location:** `Reports\`

**[evidence]** `New-ArtifactIndex.ps1:128-143` indexes Reports category.

### Category: Telemetry

| Artifact | Format | Schema | Purpose |
|----------|--------|--------|---------|
| `spans.jsonl` | JSONL | N/A | OpenTelemetry-style spans |
| `metrics.jsonl` | JSONL | N/A | Performance metrics |

**Location:** `Telemetry\`

---

## Integrity Artifacts

### artifact-index.json

**Purpose:** SHA-256 index of all artifacts in the run.

**[evidence]** `New-ArtifactIndex.ps1:169-171`
```powershell
$IndexPath = Join-Path $OutputRoot 'artifact-index.json'
$Artifacts | ConvertTo-Json -Depth 10 | Set-Content -Path $IndexPath -Encoding utf8NoBOM
```

**Schema:** `artifact-index.schema.json`

**Structure:**
```json
[
  {
    "path": "Logs\\Events.jsonl",
    "schemaVersion": "1.0",
    "sha256": "a3c9f12e8b5d3c1a2e4f6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7",
    "category": "Logs",
    "size": 12345
  }
]
```

### manifest.json

**Purpose:** Cryptographic integrity summary with Merkle root and events chain head.

**[evidence]** `Write-Manifest.ps1:54-64`
```powershell
$Manifest = @{
    schemaVersion = $SchemaVersion
    runId = $Context.RunId
    artifactCount = $Artifacts.Count
    merkleRoot = $MerkleRoot
    eventsChainHead = $EventsChainHead
    generatedAt = (Get-Date).ToUniversalTime().ToString('o')
}
```

**Schema:** `manifest.schema.json`

**Structure:**
```json
{
  "schemaVersion": "1.0",
  "runId": "abc123-...",
  "artifactCount": 17,
  "merkleRoot": "f7c3bc1d808e04732adf679965ccc34ca7ae3441...",
  "eventsChainHead": "a3c9f12e8b5d3c1a2e4f6b7c8d9e0f1a2b3c4d5e6...",
  "generatedAt": "2026-01-23T10:10:00Z"
}
```

### Events.jsonl Hash Chain

**Purpose:** Immutable event timeline with tamper detection.

**[evidence]** Referenced in `Write-Manifest.ps1:35-42` (chain head computation)

**Chain Structure:**
```
Event 1 (Genesis):  prevHash = ""
Event 2:            prevHash = SHA256(JSON of Event 1)
Event 3:            prevHash = SHA256(JSON of Event 2)
...
Event N:            prevHash = SHA256(JSON of Event N-1)
```

**Chain Head:** `manifest.eventsChainHead` = SHA256(JSON of Event N)

---

## run.json - Run Metadata

**Purpose:** Top-level run metadata including final exit code.

**[evidence]** `Invoke-PatchPilotRun.ps1:479-505` (Write-RunJson function)

**Structure:**
```json
{
  "schemaVersion": "1.0",
  "parameterSet": "Online",
  "runId": "abc123-...",
  "tenantId": "MSP001",
  "clientId": "ACME",
  "siteId": "HQ",
  "deviceId": "WIN-SERVER01",
  "configPath": "C:\\PatchPilot\\config.json",
  "outputRoot": "C:\\PatchPilot\\Output\\Runs\\abc123-...",
  "startTimeUtc": "2026-01-23T10:00:00Z",
  "endTimeUtc": "2026-01-23T10:10:00Z",
  "resumed": false,
  "testMode": false,
  "exitCode": 0
}
```

**Fields:**
| Field | Type | Description |
|-------|------|-------------|
| `parameterSet` | string | "Online", "Offline" (TestMode), or "Resume" |
| `runId` | GUID | Unique run identifier |
| `tenantId` | string | MSP tenant identifier |
| `clientId` | string | Client/customer identifier |
| `siteId` | string | Site/location identifier |
| `deviceId` | string | Device hostname (default: $env:COMPUTERNAME) |
| `startTimeUtc` | ISO 8601 | Run start timestamp |
| `endTimeUtc` | ISO 8601 | Run completion timestamp |
| `resumed` | boolean | True if this was a resume after reboot |
| `testMode` | boolean | True if -TestMode was specified |
| `exitCode` | integer | Final exit code (see below) |

---

## Exit Code Reference

Exit codes are determined **evidence-first** from persisted artifacts.

**[evidence]** `Get-PatchPilotExitCodeFromEvidence.ps1`

| Code | Name | Evidence Source |
|------|------|-----------------|
| **0** | Success | No failure indicators in any artifact |
| **100** | PartialSuccess | Reserved (not currently emitted) |
| **150** | RebootRequired | `reboot-required.json` exists OR `install-summary.jsonl` has `rebootRequired=true` |
| **170** | ConcurrencyLock | Lock acquisition failed (early exit) |
| **210** | InstallFailure | `install-summary.jsonl` has any `installed=false` |
| **220** | ValidationFailure | `regressions.json` has `TotalRegressions > 0` |
| **230** | DiagnosticsFailure | Phase09 required=true and status=Fail |
| **240** | ReportingFailure | Phase11 failed or unhandled exception |

### Exit Code Determination Flow

```
1. Check regressions.json → TotalRegressions > 0? → Return 220
2. Check install-summary.jsonl → Any installed=false? → Return 210
3. Check reboot cookie → Exists? → Return 150
4. Check install-summary → rebootRequired=true AND Phase07 incomplete? → Return 150
5. Check final-report.json → Missing after Phase11? → Return 240
6. Return 0 (Success)
```

---

## Per-Device State Files

### lock.json

**Purpose:** Prevents concurrent PatchPilot runs on the same device.

**Location:** `State\Tenants\<T>\Clients\<C>\Sites\<S>\Devices\<D>\lock.json`

**[evidence]** `Invoke-PatchPilotRun.ps1:300-307`

**Structure:**
```json
{
  "schemaVersion": "1.0",
  "lockId": "abc123-...",
  "acquiredUtc": "2026-01-23T10:00:00Z",
  "runId": "def456-...",
  "pid": 12345,
  "host": "WIN-SERVER01"
}
```

**Stale Lock Recovery:** If `lockTtlMinutes` (default 120) has passed and the PID is not running, lock is auto-removed.

### reboot-required.json

**Purpose:** Signals reboot needed; enables resume after reboot.

**Location:** `State\Tenants\<T>\Clients\<C>\Sites\<S>\Devices\<D>\reboot-required.json`

**Structure:**
```json
{
  "schemaVersion": "1.0",
  "runId": "abc123-...",
  "runRoot": "C:\\PatchPilot\\Output\\Runs\\abc123-...",
  "createdUtc": "2026-01-23T10:05:00Z",
  "reason": "Phase06 detected pending reboot"
}
```

**Consumed Cookies:** After resume, cookie is moved to `reboot-required.consumed.<timestamp>.json` for audit trail.

### diagnostics-run-history.json

**Purpose:** Tracks diagnostics collection history for throttling.

**Location:** `State\Tenants\<T>\Clients\<C>\Sites\<S>\Devices\<D>\diagnostics-run-history.json`

**Structure:**
```json
{
  "history": [
    {
      "runId": "abc123-...",
      "timestamp": "2026-01-23T10:00:00Z",
      "profile": "LightDiag",
      "triggeredBy": ["InstallFailure"]
    }
  ]
}
```

**Throttling:** Only last 50 entries are retained (see `Invoke-Phase09.ps1:541-543`).

---

## Schema Files Reference

All schemas are located in `data/schemas/`.

| Schema File | Validates |
|-------------|-----------|
| `artifact-index.schema.json` | `artifact-index.json` |
| `baseline.schema.json` | `Artifacts\Baseline\*\baseline.json` |
| `diagnostics-run-history.schema.json` | Per-device `diagnostics-run-history.json` |
| `diagnostics-summary.schema.json` | `Artifacts\Diagnostics\LightDiag\*\diagnostics-summary.json` |
| `diff-report.schema.json` | `Reports\diff-report.json` |
| `events.schema.json` | `Logs\Events.jsonl` (per line) |
| `final-report.schema.json` | `Reports\final-report.json` |
| `install-summary.schema.json` | `Logs\install-summary.jsonl` (per line) |
| `manifest.schema.json` | `manifest.json` |
| `reboot-plan.schema.json` | `State\RebootPlan.json` |
| `regressions.schema.json` | `Reports\regressions.json` |
| `snapshot.schema.json` | `Artifacts\Snapshot\*\snapshot.json` |
| `validation-result.schema.json` | `Reports\pre-validation.json`, `Reports\post-validation.json` |

---

## Artifact Verification Procedures

### Verify Event Chain Integrity

```powershell
$EventsPath = 'Logs\Events.jsonl'
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

### Verify Merkle Root

```powershell
# Re-compute Merkle root from artifact-index.json
$Index = Get-Content 'artifact-index.json' -Raw | ConvertFrom-Json
$Hashes = $Index | ForEach-Object { $_.sha256 } | Sort-Object

function Get-MerkleRoot {
    param([string[]]$Hashes)
    if ($Hashes.Count -eq 0) { return '' }
    if ($Hashes.Count -eq 1) { return $Hashes[0] }

    $HashAlg = [System.Security.Cryptography.SHA256]::Create()
    $CurrentLevel = $Hashes

    while ($CurrentLevel.Count -gt 1) {
        $NextLevel = @()
        for ($I = 0; $I -lt $CurrentLevel.Count; $I += 2) {
            if ($I + 1 -lt $CurrentLevel.Count) {
                $Combined = $CurrentLevel[$I] + $CurrentLevel[$I + 1]
                $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Combined)
                $Hash = [BitConverter]::ToString($HashAlg.ComputeHash($Bytes)).Replace('-','').ToLower()
                $NextLevel += $Hash
            } else {
                $NextLevel += $CurrentLevel[$I]
            }
        }
        $CurrentLevel = $NextLevel
    }
    return $CurrentLevel[0]
}

$ComputedRoot = Get-MerkleRoot -Hashes $Hashes
$Manifest = Get-Content 'manifest.json' -Raw | ConvertFrom-Json

if ($ComputedRoot -eq $Manifest.merkleRoot) {
    Write-Host "Merkle root verified: $ComputedRoot"
} else {
    Write-Error "Merkle root mismatch! Expected: $($Manifest.merkleRoot), Got: $ComputedRoot"
}
```

### Verify Events Chain Head

```powershell
$EventsPath = 'Logs\Events.jsonl'
$LastLine = Get-Content $EventsPath | Select-Object -Last 1

$Sha256 = [System.Security.Cryptography.SHA256]::Create()
$LineBytes = [System.Text.Encoding]::UTF8.GetBytes($LastLine)
$ComputedHead = [BitConverter]::ToString($Sha256.ComputeHash($LineBytes)).Replace('-','').ToLower()

$Manifest = Get-Content 'manifest.json' -Raw | ConvertFrom-Json

if ($ComputedHead -eq $Manifest.eventsChainHead) {
    Write-Host "Events chain head verified"
} else {
    Write-Error "Events chain head mismatch!"
}
```

---

## Interpreting Final Reports

### final-report.json Structure

```json
{
  "schemaVersion": "1.0",
  "reportType": "FinalReport",
  "status": "Success",
  "runId": "abc123-...",
  "tenantId": "MSP001",
  "clientId": "ACME",
  "siteId": "HQ",
  "deviceId": "WIN-SERVER01",
  "startTimeUtc": "2026-01-23T10:00:00Z",
  "endTimeUtc": "2026-01-23T10:10:00Z",
  "summary": {
    "installSummary": {
      "totalUpdates": 3,
      "installed": 3,
      "failed": 0,
      "rebootRequired": false
    },
    "preValidation": { "totalChecks": 10, "passed": 10 },
    "postValidation": { "totalChecks": 10, "passed": 10 },
    "regressions": { "total": 0, "apps": 0 },
    "snapshotDiff": {
      "servicesAdded": 0,
      "servicesRemoved": 0,
      "servicesChanged": 1
    },
    "diagnostics": {
      "status": "Success",
      "collectorsRun": 3,
      "totalSizeBytes": 1048576
    },
    "artifacts": {
      "total": 17,
      "merkleRoot": "f7c3bc1d...",
      "eventsChainHead": "a3c9f12e..."
    }
  },
  "paths": { /* relative paths to all artifacts */ },
  "standardsEvidenceMap": { /* NIST, CIS mappings */ }
}
```

### Quick Report Queries

```powershell
$Report = Get-Content 'Reports\final-report.json' -Raw | ConvertFrom-Json

# Overall status
Write-Host "Status: $($Report.status)"

# Install summary
Write-Host "Updates: $($Report.summary.installSummary.totalUpdates) total, $($Report.summary.installSummary.installed) installed"

# Regressions
Write-Host "Regressions: $($Report.summary.regressions.total)"

# Diagnostics
Write-Host "Diagnostics: $($Report.summary.diagnostics.status)"
```

---

## See Also

- [Artifacts & Schemas](Artifacts-and-Schemas.md) - Detailed schema documentation
- [Exit Codes](Exit-Codes.md) - Complete exit code reference
- [Directory Layout](../APPENDICES/Directory-Layout.md) - Full directory tree
- [Evidence Verification](../OPERATIONS/Evidence-Verification.md) - Verification procedures
- [Security Model](../SECURITY-COMPLIANCE/Security-Model-and-Redaction.md) - Integrity mechanisms
- [Compliance Mapping](../SECURITY-COMPLIANCE/Compliance-Mapping.md) - Standards evidence mapping
