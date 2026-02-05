# Directory Layout

## Overview

This document provides a comprehensive reference for PatchPilot's directory structure, covering both the source code repository layout and the runtime output structure.

**Referenced Code:**
- Output skeleton: `src/PatchPilot.Engine/Public/Invoke-PatchPilotRun.ps1:92-114`
- Artifact indexing: `src/PatchPilot.Engine/Private/New-ArtifactIndex.ps1`
- Per-device state: `src/PatchPilot.Engine/Public/Invoke-PatchPilotRun.ps1:239-241`

---

## Repository Structure

```
PatchPilot\
├── src\
│   ├── PatchPilot.ps1                       # Console runner wrapper
│   └── PatchPilot.Engine\
│       ├── PatchPilot.Engine.psd1           # Module manifest
│       ├── Public\                          # Exported functions
│       │   ├── Invoke-PatchPilotRun.ps1     # Main entry point
│       │   ├── Get-PatchPilotExitCodes.ps1  # Exit code constants
│       │   ├── Get-PatchPilotExitCodeFromEvidence.ps1
│       │   └── Get-PatchPilotVersion.ps1
│       └── Private\                         # Internal functions
│           ├── Initialize-RunContext.ps1   # Context initialization
│           ├── New-EventRecord.ps1          # Hash-chained events
│           ├── Invoke-Phase01.ps1           # Init phase
│           ├── Invoke-Phase02.ps1           # Baseline capture
│           ├── Invoke-Phase03.ps1           # Update catalog
│           ├── Invoke-Phase04.ps1           # Pre-validation
│           ├── Invoke-Phase05.ps1           # Patch install
│           ├── Invoke-Phase06.ps1           # Reboot orchestration
│           ├── Invoke-Phase07.ps1           # Post-reboot snapshot
│           ├── Invoke-Phase08.ps1           # Post-validation + regression
│           ├── Invoke-Phase09.ps1           # LightDiag diagnostics
│           ├── Invoke-Phase10.ps1           # Artifact indexing
│           ├── Invoke-Phase11.ps1           # Reporting
│           ├── New-ArtifactIndex.ps1        # Build artifact index
│           ├── Write-Manifest.ps1           # Merkle root + chain head
│           └── Write-FailureFinalReport.ps1 # Failure report generation
│
├── data\
│   └── schemas\                             # JSON schemas
│       ├── artifact-index.schema.json
│       ├── baseline.schema.json
│       ├── diagnostics-run-history.schema.json
│       ├── diagnostics-summary.schema.json
│       ├── diff-report.schema.json
│       ├── events.schema.json
│       ├── final-report.schema.json
│       ├── install-summary.schema.json
│       ├── manifest.schema.json
│       ├── reboot-plan.schema.json
│       ├── regressions.schema.json
│       ├── snapshot.schema.json
│       └── validation-result.schema.json
│
├── examples\
│   ├── configs\                             # Example configuration files
│   │   ├── AppValidationPolicy.json
│   │   ├── AppValidationPolicy.sample.json
│   │   └── UpdatePolicy.json
│   └── rmm-integration\                     # RMM integration kits
│       └── n-able\
│           ├── Deploy-PatchPilot.ps1
│           ├── Run-PatchPilot.ps1
│           ├── Collect-Evidence.ps1
│           └── README.md
│
├── tests\
│   └── *.Tests.ps1                          # Pester test files
│
├── docs\                                    # MkDocs documentation
│   ├── BUILD\
│   │   └── mkdocs.yml                       # MkDocs configuration
│   ├── API\
│   ├── ARCHITECTURE\
│   ├── OPERATIONS\
│   ├── SECURITY-COMPLIANCE\
│   ├── PRODUCT\
│   ├── GUIDES\
│   └── APPENDICES\
│
```

---

## Runtime Output Structure

### OutputRoot Layout

When PatchPilot runs, it creates artifacts under `OutputRoot`. The typical default is `C:\PatchPilot\Output`.

**[evidence]** `Invoke-PatchPilotRun.ps1:92-99`
```powershell
function Initialize-OutputSkeleton {
    param([Parameter(Mandatory)][string]$RunRoot)
    foreach ($Rel in @('Logs','Artifacts','Reports','Telemetry','State')) {
        $P = Join-Path $RunRoot $Rel
        if (-not (Test-Path $P)) { New-Item -ItemType Directory -Path $P -Force | Out-Null }
    }
    ...
}
```

### Complete Output Tree

```
OutputRoot\
│
├── Runs\                                    # Per-run evidence folders
│   └── <RunId>\                             # GUID (e.g., f47ac10b-58cc-4372-a567-0e02b2c3d479)
│       │
│       ├── artifact-index.json              # SHA-256 index of all artifacts
│       ├── manifest.json                    # Merkle root + events chain head
│       ├── run.json                         # Run metadata + final exit code
│       │
│       ├── Logs\
│       │   ├── Events.jsonl                 # Hash-chained event timeline
│       │   ├── install-summary.jsonl        # Per-update install outcomes (JSONL)
│       │   └── Pipeline.log                 # Verbose pipeline log (if enabled)
│       │
│       ├── Artifacts\
│       │   │
│       │   ├── Baseline\<RunId>\
│       │   │   ├── baseline.json            # Pre-patch system snapshot
│       │   │   └── raw\                     # Raw command outputs
│       │   │       ├── services.json
│       │   │       ├── drivers.json
│       │   │       └── installed-apps.json
│       │   │
│       │   ├── Snapshot\<RunId>\
│       │   │   ├── snapshot.json            # Post-patch system snapshot
│       │   │   └── raw\
│       │   │       ├── services.json
│       │   │       ├── drivers.json
│       │   │       └── installed-apps.json
│       │   │
│       │   ├── UpdateCatalog\<RunId>\
│       │   │   └── catalog.json             # Windows Update metadata
│       │   │
│       │   ├── Validation\<RunId>\
│       │   │   ├── pre\                     # Pre-validation evidence
│       │   │   │   ├── WebApp-HealthEndpoint.json
│       │   │   │   └── ServiceX-Synthetic.json
│       │   │   └── post\                    # Post-validation evidence
│       │   │       ├── WebApp-HealthEndpoint.json
│       │   │       └── ServiceX-Synthetic.json
│       │   │
│       │   └── Diagnostics\LightDiag\<RunId>\
│       │       ├── diagnostics-summary.json # Collection summary
│       │       ├── EventLogs\               # Exported .evtx files
│       │       │   ├── System.evtx
│       │       │   └── Application.evtx
│       │       └── Files\                   # Collected system files
│       │           ├── CBS.log
│       │           └── DISM.log
│       │
│       ├── Reports\
│       │   ├── pre-validation.json          # Phase04 validation results
│       │   ├── post-validation.json         # Phase08 validation results
│       │   ├── regressions.json             # Phase08 regression comparison
│       │   ├── diff-report.json             # Baseline vs snapshot diff
│       │   ├── final-report.json            # Phase11 comprehensive report
│       │   ├── final-report.html            # Human-readable HTML report
│       │   └── redaction-log.json           # Redaction audit trail
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
                    ├── reboot-required.json         # Resume cookie (active)
                    ├── reboot-required.consumed.*.json  # Consumed cookies (audit)
                    └── diagnostics-run-history.json # Throttling state
```

---

## Directory Descriptions

### Per-Run Directories

| Directory | Contents | Purpose |
|-----------|----------|---------|
| `Runs\<RunId>\` | All run artifacts | Root for single execution |
| `Runs\<RunId>\Logs\` | Events.jsonl, install-summary.jsonl | Event timeline and install outcomes |
| `Runs\<RunId>\Artifacts\` | Baseline, Snapshot, Catalog, Diagnostics | Raw evidence artifacts |
| `Runs\<RunId>\Reports\` | Validation, regressions, final reports | Processed analysis reports |
| `Runs\<RunId>\Telemetry\` | spans.jsonl, metrics.jsonl | Performance telemetry (optional) |
| `Runs\<RunId>\State\` | state.json, RebootPlan.json | Run-specific state |

### Per-Device State Directories

**[evidence]** `Invoke-PatchPilotRun.ps1:239-240`
```powershell
$DeviceStateRoot = Join-Path $OutputRoot ("State\Tenants\$TenantId\Clients\$ClientId\Sites\$SiteId\Devices\$DeviceId")
```

| File | Purpose | Lifetime |
|------|---------|----------|
| `lock.json` | Prevents concurrent runs | Duration of run |
| `reboot-required.json` | Resume cookie for post-reboot | Until consumed |
| `reboot-required.consumed.*.json` | Audit trail of consumed cookies | Retained indefinitely |
| `diagnostics-run-history.json` | Throttling history (last 50 entries) | Ongoing |

---

## Artifact Categories

**[evidence]** `New-ArtifactIndex.ps1` scans these categories:

| Category | Location | Indexed? |
|----------|----------|----------|
| Logs | `Logs\` | Yes |
| Baseline | `Artifacts\Baseline\` | Yes |
| Snapshot | `Artifacts\Snapshot\` | Yes |
| UpdateCatalog | `Artifacts\UpdateCatalog\` | Yes |
| Validation | `Artifacts\Validation\` | Yes |
| Diagnostics/LightDiag | `Artifacts\Diagnostics\LightDiag\` | Yes |
| Reports | `Reports\` | Yes |
| Telemetry | `Telemetry\` | Yes (excluding staging files) |

---

## Path Conventions

### RunId

- **Format:** GUID string (e.g., `f47ac10b-58cc-4372-a567-0e02b2c3d479`)
- **Generated:** At run start (or inherited from reboot cookie)
- **Usage:** Subdirectory name under `Runs\`, embedded in all artifacts

### Multi-Tenant Path Structure

```
State\Tenants\<TenantId>\Clients\<ClientId>\Sites\<SiteId>\Devices\<DeviceId>\
```

**Defaults:**
| Parameter | Default Value |
|-----------|---------------|
| TenantId | `T0` |
| ClientId | `C0` |
| SiteId | `S0` |
| DeviceId | `$env:COMPUTERNAME` |

**Example Path:**
```
C:\PatchPilot\Output\State\Tenants\MSP001\Clients\ACME\Sites\HQ\Devices\WIN-SERVER01\
```

---

## File Naming Conventions

### JSON Artifacts

| File | Naming Pattern | Example |
|------|----------------|---------|
| Run metadata | `run.json` | `run.json` |
| Artifact index | `artifact-index.json` | `artifact-index.json` |
| Manifest | `manifest.json` | `manifest.json` |
| Event log | `Events.jsonl` | `Events.jsonl` |
| Install summary | `install-summary.jsonl` | `install-summary.jsonl` |
| Baseline | `baseline.json` | `baseline.json` |
| Snapshot | `snapshot.json` | `snapshot.json` |
| Update catalog | `catalog.json` | `catalog.json` |
| Validation results | `pre-validation.json`, `post-validation.json` | `pre-validation.json` |
| Regressions | `regressions.json` | `regressions.json` |
| Diff report | `diff-report.json` | `diff-report.json` |
| Final report | `final-report.json`, `final-report.html` | `final-report.json` |
| Diagnostics summary | `diagnostics-summary.json` | `diagnostics-summary.json` |

### Consumed Cookies

**Pattern:** `reboot-required.consumed.<timestamp>.json`
**Example:** `reboot-required.consumed.20260123T101000Z.json`

---

## Storage Estimation

| Component | Typical Size | Notes |
|-----------|--------------|-------|
| Events.jsonl | 50-200 KB | Depends on phase count |
| install-summary.jsonl | 1-10 KB | One line per update |
| baseline.json | 100-500 KB | Services + drivers + apps |
| snapshot.json | 100-500 KB | Same as baseline |
| catalog.json | 10-100 KB | Depends on pending updates |
| Validation evidence | 10-50 KB | Per check |
| Diagnostics (LightDiag) | 1-50 MB | Event logs + CBS logs |
| Final report | 10-50 KB | Summary + paths |
| **Total per run** | **2-60 MB** | Without heavy diagnostics |

See [Data Retention](../SECURITY-COMPLIANCE/Data-Retention.md) for storage planning and cleanup.

---

## Permissions Requirements

### Recommended NTFS Permissions

| Path | Principal | Permission |
|------|-----------|------------|
| `OutputRoot` | SYSTEM | Full Control |
| `OutputRoot` | Administrators | Full Control |
| `OutputRoot` | RMM Service Account | Modify |
| `OutputRoot\State\` | SYSTEM | Full Control |
| `OutputRoot\State\` | Administrators | Full Control |

### Per-Device State Security

The per-device state directory contains sensitive operational data (locks, cookies). Restrict access to SYSTEM and local Administrators.

---

## See Also

- [Output Artifact Reference](../API/Output-Artifact-Reference.md) - Detailed artifact documentation
- [Artifacts & Schemas](../API/Artifacts-and-Schemas.md) - Schema reference
- [Data Retention](../SECURITY-COMPLIANCE/Data-Retention.md) - Retention policies
- [Security Model](../SECURITY-COMPLIANCE/Security-Model-and-Redaction.md) - Access control guidance
