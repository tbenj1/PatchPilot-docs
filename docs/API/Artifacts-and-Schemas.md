# Artifacts & Schemas

All PatchPilot artifacts are JSON (or JSONL) with UTF-8 encoding (no BOM).

## Directory Layout

```
OutputRoot\
├── artifact-index.json          # SHA-256 index of all artifacts
├── manifest.json                 # Merkle root + events chain head
├── Logs\
│   ├── Events.jsonl              # Hash-chained event log
│   └── install-summary.jsonl     # Per-update install outcomes
├── Artifacts\
│   ├── Baseline\
│   │   ├── baseline.json         # Pre-patch snapshot
│   │   └── raw\*                 # Raw command outputs
│   ├── Snapshot\
│   │   ├── snapshot.json         # Post-patch snapshot
│   │   └── raw\*
│   ├── UpdateCatalog\
│   │   └── catalog.json          # Windows Update metadata
│   └── Diagnostics\LightDiag\<RunId>\
│       └── diagnostics-summary.json
├── Reports\
│   ├── pre-validation.json
│   ├── post-validation.json
│   ├── regressions.json
│   └── final-report.json
├── Telemetry\                   # (Optional; if enabled)
│   ├── spans.jsonl
│   └── metrics.jsonl
└── State\
    ├── state.json                # Checkpoint data
    └── RebootPlan.json           # Reboot orchestration

Device-scoped state (outside the run folder):

OutputRoot\State\Tenants\<TenantId>\Clients\<ClientId>\Sites\<SiteId>\Devices\<DeviceId>\
├── lock.json                      # Concurrency guard
└── diagnostics-run-history.json
    └── reboot.cookie             # Resume marker
```

See [Directory Layout](../APPENDICES/Directory-Layout.md) for full tree.

---

## Schema Reference

All schemas are in `data/schemas/*.schema.json`.

### events.schema.json

**Location:** `data/schemas/events.schema.json`

**Purpose:** Structured event log with hash chaining

**Required Fields:**
- `timestamp` (ISO 8601 UTC)
- `runId` (UUID)
- `event` (string) - Event name (e.g., "PhaseStart", "PatchInstallStart")
- `level` (enum: "Info", "Warning", "Error")
- `prevHash` (SHA-256 hex, empty for genesis event)
- `data` (object) - Event payload

**Example:**
```json
{
  "timestamp": "2026-01-23T10:00:00Z",
  "runId": "abc123-...",
  "event": "PhaseStart",
  "level": "Info",
  "prevHash": "b9f1c2...",
  "data": {
    "phaseId": "Phase05",
    "name": "Patch Install"
  }
}
```

**Hash Chaining:** Each event's `prevHash` is the SHA-256 of the previous event's JSON. Genesis event has `prevHash: ""`.

---

### manifest.schema.json

**Location:** `data/schemas/manifest.schema.json`

**Purpose:** Run manifest with integrity proofs

**Required Fields:**
- `runId` (UUID)
- `merkleRoot` (SHA-256 hex) - Merkle tree root over artifact hashes
- `artifactCount` (integer)
- `eventsChainHead` (SHA-256 hex) - Hash of final event in Events.jsonl

**Optional Fields:**
- `timestamp`, `tenantId`, `clientId`, `deviceId`

**Example:**
```json
{
  "runId": "abc123-...",
  "merkleRoot": "f7c3bc1d808e04732adf679965ccc34ca7ae3441",
  "artifactCount": 17,
  "eventsChainHead": "a3c9f12e8b5d3c1a2e4f6b7c8d9e0f1a2b3c4d5e6",
  "timestamp": "2026-01-23T10:10:00Z",
  "tenantId": "MSP001",
  "clientId": "ACME",
  "deviceId": "WIN-SERVER01"
}
```

---

### artifact-index.schema.json

**Location:** `data/schemas/artifact-index.schema.json`

**Purpose:** SHA-256 index of all artifacts

**Structure:** Array of objects with:
- `path` (string) - Relative path from OutputRoot
- `sha256` (SHA-256 hex)
- `category` (string) - e.g., "Baseline", "Logs", "Reports"
- `size` (integer) - Bytes

**Example:**
```json
[
  {
    "path": "Artifacts/Baseline/abc123.../baseline.json",
    "sha256": "d2a84f4b8b650937ec8f73cd8be2c74add5a911ba64df27458ed8229da804a26",
    "category": "Baseline",
    "size": 4096
  },
  {
    "path": "Logs/install-summary.jsonl",
    "sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    "category": "Logs",
    "size": 512
  }
]
```

---

### install-summary.schema.json

**Location:** `data/schemas/install-summary.schema.json`

**Purpose:** Per-update install outcomes (JSONL format)

**JSONL Structure:** One JSON object per line

**Required Fields:**
- `kb` (string)
- `title` (string)
- `classification` (string)
- `downloaded` (boolean)
- `installed` (boolean)
- `hresult` (integer) - Windows HRESULT code
- `rebootRequired` (boolean)
- `durationMs` (integer)

**Example Line:**
```json
{"kb":"KB5012345","title":"2026-01 Cumulative","classification":"SecurityUpdates","downloaded":true,"installed":true,"hresult":0,"rebootRequired":false,"durationMs":42110}
```

**Usage:** Read by exit code logic (lines 260-287 of `Invoke-PatchPilotRun.ps1`) and Phase11 reporting.

---

### baseline.schema.json / snapshot.schema.json

**Location:** `data/schemas/baseline.schema.json`, `data/schemas/snapshot.schema.json`

**Purpose:** Pre/post-patch system snapshots (identical schemas for parity)

**Required Fields:**
- `runId` (UUID)
- `timestamp` (ISO 8601 UTC)

**Snapshot Categories (inferred from design):**
- `services` - Array of `{ name, status, startType }`
- `drivers` - Array of `{ name, version, provider }`
- `installedApps` - Array of `{ name, version, publisher }`
- `updateSettings` - `{ autoUpdateEnabled, lastSuccessTime }`
- `perfConfig` - (Inferred) Performance/config baselines

**Example:**
```json
{
  "runId": "abc123...",
  "timestamp": "2026-01-23T10:01:00Z",
  "services": [
    { "name": "wuauserv", "status": "Running", "startType": "Automatic" }
  ],
  "drivers": [
    { "name": "nvlddmkm", "version": "30.0.15.1179", "provider": "NVIDIA" }
  ],
  "installedApps": [
    { "name": "Microsoft Edge", "version": "120.0.2210.121", "publisher": "Microsoft" }
  ],
  "updateSettings": {
    "autoUpdateEnabled": true,
    "lastSuccessTime": "2026-01-20T03:00:00Z"
  }
}
```

**Parity Requirement:** Phase02 and Phase07 must capture **identical keys** to enable diff in Phase11.

---

### validation-result.schema.json

**Location:** `data/schemas/validation-result.schema.json`

**Purpose:** Pre/post-validation results

**Structure:**
- `runId`, `timestamp`
- `when` ("Pre" or "Post")
- `applications` - Array of:
  - `name` (string)
  - `checks` - Array of:
    - `pattern` (string) - e.g., "HealthEndpoint", "Synthetic", "Process"
    - `success` (boolean)
    - `confidence` (float 0.0-1.0)
    - `evidencePath` (string) - Path to raw evidence
    - `notes` (string)
  - `overallConfidence` (float)

**Example:**
```json
{
  "runId": "abc123...",
  "timestamp": "2026-01-23T10:03:00Z",
  "when": "Pre",
  "applications": [
    {
      "name": "WebApp",
      "checks": [
        {
          "pattern": "HealthEndpoint",
          "success": true,
          "confidence": 1.0,
          "evidencePath": "Reports/abc123.../validation-evidence/pre-WebApp-HealthEndpoint.json",
          "notes": "HTTP 200 OK"
        }
      ],
      "overallConfidence": 1.0
    }
  ]
}
```

---

### regressions.schema.json

**Location:** `data/schemas/regressions.schema.json`

**Purpose:** Detected regressions (Phase08)

**Structure:**
- `runId`, `timestamp`
- `TotalRegressions` (integer)
- `applications` - Array of:
  - `name` (string)
  - `regressions` - Array of:
    - `pattern` (string)
    - `preSuccess` (boolean)
    - `postSuccess` (boolean)
    - `preConfidence` (float)
    - `postConfidence` (float)
    - `notes` (string)

**Example:**
```json
{
  "runId": "abc123...",
  "timestamp": "2026-01-23T10:08:00Z",
  "TotalRegressions": 1,
  "applications": [
    {
      "name": "WebApp",
      "regressions": [
        {
          "pattern": "HealthEndpoint",
          "preSuccess": true,
          "postSuccess": false,
          "preConfidence": 1.0,
          "postConfidence": 0.0,
          "notes": "HTTP 500 after patching (was 200 PRE)"
        }
      ]
    }
  ]
}
```

---

### reboot-plan.schema.json

**Location:** `data/schemas/reboot-plan.schema.json`

**Purpose:** Reboot orchestration metadata

**Structure:**
- `nextPhase` (string) - e.g., "Phase07"
- `returnPath` (string) - Script path to resume (inferred)
- `cookie` (string) - Path to cookie file
- `timestamp` (ISO 8601 UTC)

**Example:**
```json
{
  "nextPhase": "Phase07",
  "returnPath": "C:\\PatchPilot\\Engine\\Resume.ps1",
  "cookie": "State\\reboot.cookie",
  "timestamp": "2026-01-23T10:05:00Z"
}
```

---

### diagnostics-summary.schema.json

**Location:** `data/schemas/diagnostics-summary.schema.json`

**Purpose:** Phase09 LightDiag collection summary (what ran, why it ran, what it produced, and whether caps were exceeded).

**Structure (high-level):**
- `schemaVersion`, `runId`, `generatedUtc`
- `profile` (string)
- `mode` (enum) — `Never` | `OnFailure` | `Always`
- `status` (enum) — `Success` | `Partial` | `Fail`
- `triggeredBy` (array of strings)
- `caps` — `{ maxRuntimeSeconds, maxTotalOutputMb, maxPerArtifactMb }`
- `throttlingWindowMin`, `capExceeded`, `durationMs`
- `collectors` — per-collector summary `{ name, status, artifacts, bytes, notes? }`
- `artifacts` — per-artifact list `{ collector, name, path, sizeBytes, sha256 }`

**Example:**
```json
{
  "schemaVersion": "1.0",
  "runId": "abc123...",
  "generatedUtc": "2026-01-23T10:09:00Z",
  "profile": "LightDiag",
  "mode": "OnFailure",
  "status": "Success",
  "triggeredBy": ["InstallFailure"],
  "caps": {
    "maxRuntimeSeconds": 600,
    "maxTotalOutputMb": 200,
    "maxPerArtifactMb": 50
  },
  "throttlingWindowMin": 60,
  "capExceeded": false,
  "durationMs": 12345,
  "totalArtifacts": 4,
  "totalBytes": 1048576,
  "collectors": [
    { "name": "EventLog", "status": "Success", "artifacts": 1, "bytes": 123456 },
    { "name": "Files", "status": "Success", "artifacts": 2, "bytes": 789012 },
    { "name": "Commands", "status": "Skipped", "artifacts": 0, "bytes": 0 }
  ],
  "artifacts": [
    {
      "collector": "EventLog",
      "name": "System.evtx",
      "path": "Artifacts/Diagnostics/LightDiag/abc123.../EventLog/System.evtx",
      "sizeBytes": 123456,
      "sha256": "a3c9f12e8b5d3c1a2e4f6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7"
    }
  ]
}
```

---

### final-report.schema.json

**Location:** `data/schemas/final-report.schema.json`

**Purpose:** Phase11 evidence-first final report. This file is built **only** from artifacts on disk (no re-computation from in-memory state).

**Structure (high-level):**
- `runId`, `tenantId`, `clientId`, `siteId`, `deviceId`, `generatedAt`
- `summary` — summarized counts for install, validation, regressions, snapshot diff, diagnostics, and integrity
- `paths` — relative evidence paths (includes `paths.diagnosticsSummary`)
- `standardsEvidenceMap` — compliance mappings

**Example:**
```json
{
  "runId": "abc123...",
  "tenantId": "MSP001",
  "clientId": "ACME",
  "siteId": "HQ",
  "deviceId": "WIN-SERVER01",
  "generatedAt": "2026-01-23T10:10:00Z",
  "summary": {
    "installSummary": { "totalUpdates": 3, "installed": 3, "failed": 0, "rebootRequired": false },
    "preValidation": { "totalChecks": 10, "passed": 10 },
    "postValidation": { "totalChecks": 10, "passed": 10 },
    "regressions": { "total": 0, "apps": 0 },
    "snapshotDiff": { "servicesAdded": 0, "servicesRemoved": 0, "servicesChanged": 0 },
    "diagnostics": { "collectorsRun": 3, "totalSizeBytes": 1048576 },
    "artifacts": {
      "total": 17,
      "merkleRoot": "f7c3bc1d808e04732adf679965ccc34ca7ae3441f7c3bc1d808e04732adf6799",
      "eventsChainHead": "a3c9f12e8b5d3c1a2e4f6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7"
    }
  },
  "paths": {
    "installSummary": "Logs/install-summary.jsonl",
    "preValidation": "Reports/pre-validation.json",
    "postValidation": "Reports/post-validation.json",
    "regressions": "Reports/regressions.json",
    "baseline": "Artifacts/Baseline/abc123.../baseline.json",
    "snapshot": "Artifacts/Snapshot/abc123.../snapshot.json",
    "diffReport": "Reports/system-diff.json",
    "diagnosticsSummary": "Artifacts/Diagnostics/LightDiag/abc123.../diagnostics-summary.json",
    "artifactIndex": "artifact-index.json",
    "manifest": "manifest.json",
    "events": "Logs/Events.jsonl"
  },
  "standardsEvidenceMap": { }
}
```

---

## Configuration Schemas (Policy Files)

Policies are in `examples/configs/*.json`.

### UpdatePolicy.json

**Location:** `examples/configs/UpdatePolicy.json`

**Structure:**
- `policyId`, `version`
- `updateSettings`:
  - `autoApprove` (boolean)
  - `classifications` - Array of strings (e.g., "Critical", "SecurityUpdates")
  - `excludedKBs`, `includedKBs` - Arrays
  - `deferralDays` (integer) - Reboot deferral window
  - `maintenanceWindow` - Optional scheduling
- `rebootSettings`:
  - `allowAutoReboot` (boolean)
  - `rebootDelayMinutes` (integer)
- `downloadSettings`:
  - `useBITS` (boolean)
  - `maxBandwidthKbps` (integer)

See [Policy Authoring](../GUIDES/Policy-Authoring.md) for details.

---

### AppValidationPolicy.json

**Location:** `examples/configs/AppValidationPolicy.json`

**Structure:**
- `CaptureHttpBodies` (boolean)
- `applications` - Array of:
  - `name` (string)
  - `patterns` - Array of:
    - `type` ("HealthEndpoint", "Synthetic", "Process")
    - Type-specific fields (e.g., `url`, `command`, `target`)

**Example:**
```json
{
  "CaptureHttpBodies": true,
  "applications": [
    {
      "name": "WebApp",
      "patterns": [
        {
          "type": "HealthEndpoint",
          "url": "https://example.com/health",
          "expectedStatus": 200
        }
      ]
    }
  ]
}
```

---

### diagnostics config (top-level "diagnostics" block)

**Location:** `examples/configs/diagnostics config (top-level "diagnostics" block)`

**Structure:**
- `DefaultProfile` ("Light", "Standard", "Deep")
- `Triggers`:
  - `InstallFailure` (boolean)
  - `Regressions` (boolean)
  - `RepeatedErrors` (boolean)
- `Caps`:
  - `MaxSizeMB` (integer)
  - `MaxMinutes` (integer)
- `ThrottlingWindowMin` (integer) - Cooldown between collections

**Example:**
```json
{
  "DefaultProfile": "Standard",
  "Triggers": {
    "InstallFailure": true,
    "Regressions": true,
    "RepeatedErrors": false
  },
  "Caps": {
    "MaxSizeMB": 100,
    "MaxMinutes": 15
  },
  "ThrottlingWindowMin": 60
}
```

---

## Artifact Verification

### Verify Hash Chain (Events.jsonl)

```powershell
$eventsPath = 'Logs\Events.jsonl'
$lines = Get-Content $eventsPath

for ($i = 1; $i -lt $lines.Count; $i++) {
    $prev = $lines[$i - 1] | ConvertFrom-Json
    $curr = $lines[$i] | ConvertFrom-Json

    $expectedHash = (Get-FileHash -InputStream ([IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes($lines[$i - 1]))) -Algorithm SHA256).Hash.ToLower()

    if ($curr.prevHash -ne $expectedHash) {
        Write-Error "Chain broken at line $i"
    }
}
Write-Output "Event chain verified"
```

### Verify Merkle Root

```powershell
$index = Get-Content 'artifact-index.json' -Raw | ConvertFrom-Json
$hashes = $index | ForEach-Object { $_.sha256 } | Sort-Object
$concatenated = $hashes -join ''
$computedRoot = (Get-FileHash -InputStream ([IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes($concatenated))) -Algorithm SHA256).Hash.ToLower()

$manifest = Get-Content 'manifest.json' -Raw | ConvertFrom-Json
if ($computedRoot -eq $manifest.merkleRoot) {
    Write-Output "Merkle root verified"
} else {
    Write-Error "Merkle root mismatch"
}
```

See [Evidence Verification](../OPERATIONS/Evidence-Verification.md) for full procedures.

---

## References

- [PowerShell Module Reference](PowerShell-Module-Reference.md)
- [Exit Codes](Exit-Codes.md)
- [Directory Layout](../APPENDICES/Directory-Layout.md)
- [JSON Examples](../APPENDICES/JSON-Examples.md)
- [Evidence Verification](../OPERATIONS/Evidence-Verification.md)
