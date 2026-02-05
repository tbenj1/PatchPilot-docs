# Security Model & Redaction

## Overview

PatchPilot implements a defense-in-depth security model designed for multi-tenant MSP environments. This document describes threat model assumptions, confidentiality boundaries, redaction controls, evidence integrity mechanisms, and operational security guidance.

**Referenced Code:**
- Redaction implementation: `src/PatchPilot.Engine/Private/Invoke-Phase11.ps1:423-455`
- Hash chaining: `src/PatchPilot.Engine/Private/New-EventRecord.ps1`
- Merkle root integrity: `src/PatchPilot.Engine/Private/Write-Manifest.ps1:74-111`
- Concurrency lock: `src/PatchPilot.Engine/Public/Invoke-PatchPilotRun.ps1:48-91`

---

## Threat Model Assumptions

### In Scope (What PatchPilot Protects Against)

| Threat | Mitigation |
|--------|------------|
| Evidence tampering (post-run) | SHA-256 hash chains, Merkle roots, artifact index |
| Concurrent execution conflicts | Atomic file-based locks with TTL |
| State corruption after reboot | Persistent checkpoints and reboot cookies |
| Unauthorized run impersonation | TenantId/ClientId/DeviceId scoping in all artifacts |
| Sensitive data in reports | Redaction policy engine (`ReportingPolicy.json`) |
| Audit log gaps | Hash-chained Events.jsonl with genesis event |

### Out of Scope (Assumptions)

1. **Local Admin Trust**: PatchPilot requires local administrator privileges. A malicious local admin can bypass all controls.
2. **Pre-Run Tampering**: PatchPilot does not validate the integrity of its own binaries or configuration files before execution.
3. **Network-Level Attacks**: Windows Update transport security is delegated to the OS.
4. **Physical Access**: No protection against physical machine access.
5. **Policy Authenticity**: PatchPilot does not cryptographically verify policy file signatures.

---

## Confidentiality Boundaries

### Data Collected

PatchPilot collects and persists the following categories of data:

| Category | Artifacts | Sensitive? | Redaction Available? |
|----------|-----------|------------|---------------------|
| System Services | `baseline.json`, `snapshot.json` | Low | No |
| Installed Drivers | `baseline.json`, `snapshot.json` | Low | No |
| Installed Applications | `baseline.json`, `snapshot.json` | Low | No |
| Update Metadata | `catalog.json` | Low | No |
| Update Install Outcomes | `install-summary.jsonl` | Low | No |
| Validation Results | `pre-validation.json`, `post-validation.json` | Medium | Configurable |
| HTTP Response Bodies | Validation evidence files | High | Configurable |
| Event Log Exports | `*.evtx` (Phase09) | High | Collector disable |
| System Files | CBS.log, DISM.log (Phase09) | Medium | Collector disable |
| Device Identity | All artifacts | Low | No |
| Tenant/Client Identity | All artifacts | Low | No |

### Data NOT Collected

- User credentials or tokens
- Browser history or cookies
- Personal files or documents
- Network traffic content (unless NetTrace explicitly enabled)
- Registry hives beyond update-related keys
- Memory dumps

### Evidence:
```powershell
# From Initialize-RunContext.ps1:169-175
Telemetry = @{
    Hostname = $env:COMPUTERNAME
    Username = $env:USERNAME       # Environment username only, no secrets
    PSVersion = $PSVersionTable.PSVersion.ToString()
    OS = $PSVersionTable.OS
}
```

---

## Redaction Implementation

### Redaction Policy Configuration

Redaction is controlled by `ReportingPolicy.json` in the config directory:

```json
{
  "redaction": {
    "enabled": true,
    "fields": [
      "httpResponseBody",
      "validationNotes",
      "errorStackTrace"
    ]
  }
}
```

### Redaction Processing

**[evidence]** `src/PatchPilot.Engine/Private/Invoke-Phase11.ps1:423-455`

```powershell
function Get-RedactionLog {
    param(
        [hashtable]$Context,
        [pscustomobject]$Report
    )

    $ConfigDir = Split-Path $Context.ConfigPath -Parent
    $ReportingPolicyPath = Join-Path $ConfigDir 'ReportingPolicy.json'

    $RedactionLog = @{
        runId = $Context.RunId
        appliedAt = (Get-Date).ToUniversalTime().ToString('o')
        redactedFields = @()
    }

    if (Test-Path $ReportingPolicyPath) {
        $Policy = Get-Content $ReportingPolicyPath -Raw | ConvertFrom-Json

        if ($Policy.PSObject.Properties['redaction'] -and $Policy.redaction.enabled) {
            foreach ($Field in $Policy.redaction.fields) {
                $RedactionLog.redactedFields += @{
                    field = $Field
                    reason = 'RedactionPolicy'
                    timestamp = (Get-Date).ToUniversalTime().ToString('o')
                }
            }
        }
    }

    return $RedactionLog
}
```

### Redaction Artifacts

After Phase11 completes, the following file is created:

- **Location**: `Reports\redaction-log.json`
- **Purpose**: Audit trail of what was redacted and when

**Example:**
```json
{
  "runId": "abc123-...",
  "appliedAt": "2026-01-23T10:10:00Z",
  "redactedFields": [
    {
      "field": "httpResponseBody",
      "reason": "RedactionPolicy",
      "timestamp": "2026-01-23T10:10:00Z"
    }
  ]
}
```

### Recommended Redaction Fields

| Field | Risk Level | When to Redact |
|-------|------------|----------------|
| `httpResponseBody` | High | Always in production (may contain PII) |
| `validationNotes` | Medium | When sharing with external auditors |
| `errorStackTrace` | Low | When debugging info is sensitive |

---

## Evidence Integrity

### Hash-Chained Event Log

**[evidence]** `src/PatchPilot.Engine/Private/New-EventRecord.ps1`

Each event in `Logs\Events.jsonl` includes a `prevHash` field containing the SHA-256 hash of the previous event's JSON representation. This creates an immutable chain that detects tampering.

**Chain Structure:**
```
Genesis Event (prevHash: "")
    ↓ SHA-256
Event 2 (prevHash: hash(Genesis))
    ↓ SHA-256
Event 3 (prevHash: hash(Event 2))
    ↓ ...
Final Event (prevHash: hash(Event N-1))
```

**Example Event:**
```json
{
  "timestamp": "2026-01-23T10:00:00Z",
  "runId": "abc123-...",
  "event": "PhaseStart",
  "level": "Info",
  "prevHash": "b9f1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1",
  "data": {
    "phaseId": "Phase05",
    "name": "Patch Install"
  }
}
```

### Hash Chain Verification

```powershell
# Verify event chain integrity
$eventsPath = 'Logs\Events.jsonl'
$lines = Get-Content $eventsPath
$sha256 = [System.Security.Cryptography.SHA256]::Create()

for ($i = 1; $i -lt $lines.Count; $i++) {
    $prevJson = $lines[$i - 1]
    $prevHash = [BitConverter]::ToString(
        $sha256.ComputeHash([Text.Encoding]::UTF8.GetBytes($prevJson))
    ).Replace("-", "").ToLower()

    $currentEvent = $lines[$i] | ConvertFrom-Json
    if ($currentEvent.prevHash -ne $prevHash) {
        Write-Error "Chain broken at event $i"
        return $false
    }
}
Write-Output "Event chain verified successfully"
return $true
```

### Artifact Index and Merkle Root

**[evidence]** `src/PatchPilot.Engine/Private/Write-Manifest.ps1:74-111`

Phase10 builds a Merkle tree over all artifact SHA-256 hashes:

```
         Merkle Root
           /      \
      Hash(A+B)  Hash(C+D)
       /    \     /    \
     Hash(A) Hash(B) Hash(C) Hash(D)
       |       |       |       |
    baseline  snapshot  events  install-summary
```

**Merkle Root Computation:**
```powershell
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
                $CombinedBytes = [System.Text.Encoding]::UTF8.GetBytes($Combined)
                $HashBytes = $HashAlg.ComputeHash($CombinedBytes)
                $NextLevel += [System.BitConverter]::ToString($HashBytes).Replace('-', '').ToLower()
            } else {
                $NextLevel += $CurrentLevel[$I]
            }
        }
        $CurrentLevel = $NextLevel
    }

    return $CurrentLevel[0]
}
```

### Manifest Integrity

The `manifest.json` file contains:
- `merkleRoot`: Computed from artifact-index.json hashes
- `eventsChainHead`: SHA-256 of the final event in Events.jsonl
- `artifactCount`: Total indexed artifacts

**Example:**
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

---

## Access Control Guidance

### Evidence Folder Permissions

PatchPilot creates output under `OutputRoot\Runs\<RunId>\`. Recommended NTFS permissions:

| Principal | Permission | Scope |
|-----------|------------|-------|
| SYSTEM | Full Control | OutputRoot and all children |
| Administrators | Full Control | OutputRoot and all children |
| RMM Service Account | Modify | OutputRoot (for collection) |
| Authenticated Users | None | Remove default inheritance |

### Per-Device State Protection

Per-device state is stored under:
```
OutputRoot\State\Tenants\<TenantId>\Clients\<ClientId>\Sites\<SiteId>\Devices\<DeviceId>\
```

This path contains:
- `lock.json` - Concurrency guard
- `reboot-required.json` - Resume cookie
- `diagnostics-run-history.json` - Throttling state

**Recommendation:** Restrict this directory to SYSTEM and local Administrators only.

### Evidence Transport Security

When transmitting evidence to RMM or ITSM:
1. Use TLS 1.2+ for all transfers
2. Prefer authenticated endpoints (API keys, OAuth)
3. Consider encrypting archives before upload if channel is not end-to-end encrypted

---

## Safe Handling for External Sharing

### Preparing Evidence for Auditors

Before sharing evidence with external parties:

1. **Apply Redaction Policy**: Ensure `ReportingPolicy.json` redacts sensitive fields
2. **Verify redaction-log.json**: Confirm expected fields were redacted
3. **Remove Diagnostic Artifacts** (if containing sensitive data):
   ```powershell
   # Remove event logs before sharing (if policy permits)
   Remove-Item "Artifacts\Diagnostics\LightDiag\*\EventLogs\*" -Recurse
   ```
4. **Package with Integrity Proof**:
   ```powershell
   # Include manifest.json for Merkle root verification
   Compress-Archive -Path $RunRoot -DestinationPath "Evidence-$RunId.zip"
   ```

### Email Safety

When emailing reports:
- **DO**: Attach `final-report.html` (client-friendly)
- **DO**: Reference `manifest.merkleRoot` for verification
- **DO NOT**: Email raw `Events.jsonl` or `.evtx` files
- **DO NOT**: Include HTTP response bodies without redaction

---

## Concurrency Lock Security

**[evidence]** `src/PatchPilot.Engine/Public/Invoke-PatchPilotRun.ps1:48-91`

### Lock Mechanism

PatchPilot uses atomic file creation to prevent concurrent runs:

```powershell
function New-ExclusiveLock {
    param(
        [Parameter(Mandatory)][string]$LockPath,
        [Parameter(Mandatory)][hashtable]$LockData
    )
    try {
        $Fs = [System.IO.File]::Open($LockPath,
            [System.IO.FileMode]::CreateNew,  # Atomic create
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None)
        # ... write lock data ...
        return $true
    } catch [System.IO.IOException] {
        return $false  # Lock exists
    }
}
```

### Stale Lock Recovery

If a previous run crashed, locks may become stale. PatchPilot implements TTL-based recovery:

**[evidence]** `Invoke-PatchPilotRun.ps1:310-360`

```powershell
$LockTtlMinutes = 120  # Configurable via config.lockTtlMinutes
$AgeMinutes = ((Get-Date).ToUniversalTime() - $AcquiredTime).TotalMinutes
$PidAlive = Get-Process -Id $LockPid -ErrorAction SilentlyContinue

if ($AgeMinutes -ge $LockTtlMinutes -and -not $PidAlive) {
    # Remove stale lock and retry
    Remove-Item -LiteralPath $LockPath -Force
}
```

---

## Diagnostics Security (Phase09)

### Collector Scope Control

Phase09 collectors can capture sensitive data. Control via `diagnostics` config block:

```json
{
  "diagnostics": {
    "mode": "OnFailure",
    "eventLog": {
      "enabled": true,
      "channels": ["System", "Application"]
    },
    "files": {
      "enabled": true,
      "paths": ["%windir%\\Logs\\CBS\\CBS.log"]
    },
    "commands": {
      "enabled": false
    },
    "netTrace": {
      "enabled": false
    }
  }
}
```

### Recommendations

| Collector | Default | Recommendation |
|-----------|---------|----------------|
| EventLog | Enabled | Keep enabled; essential for troubleshooting |
| Files | Enabled | Review paths; CBS/DISM logs are low-risk |
| Commands | Disabled | Keep disabled unless specific need |
| NetTrace | Disabled | Only enable for network debugging; high PII risk |

---

## Operational Security Checklist

### Pre-Deployment
- [ ] Review and customize `ReportingPolicy.json` redaction fields
- [ ] Configure `diagnostics` block to disable unnecessary collectors
- [ ] Set appropriate NTFS permissions on OutputRoot
- [ ] Document retention policy (see [Data Retention](Data-Retention.md))

### Ongoing Operations
- [ ] Periodically verify hash chain integrity on critical runs
- [ ] Monitor for exit code 170 (concurrency lock issues)
- [ ] Archive evidence per retention schedule
- [ ] Rotate or clean stale diagnostic history

### Incident Response
- [ ] Preserve `manifest.json` for evidence integrity proof
- [ ] Export `Events.jsonl` for timeline reconstruction
- [ ] Collect `redaction-log.json` to prove what was sanitized

---

## See Also

- [Data Retention](Data-Retention.md) - Artifact lifecycle and cleanup
- [Evidence Verification](../OPERATIONS/Evidence-Verification.md) - Verification procedures
- [Audit Playbook](Audit-Playbook.md) - Audit preparation workflows
- [Compliance Mapping](Compliance-Mapping.md) - Standards evidence mapping
- [Artifacts & Schemas](../API/Artifacts-and-Schemas.md) - Complete artifact reference
