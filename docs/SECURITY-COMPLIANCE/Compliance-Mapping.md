# Compliance Mapping

## Overview

PatchPilot's evidence-first architecture provides audit-ready artifacts that map directly to major security and compliance frameworks. This document details how PatchPilot artifacts satisfy control requirements for NIST, CIS, and other standards.

**Referenced Code:**
- Standards evidence map: `src/PatchPilot.Engine/Private/Invoke-Phase11.ps1:318-420`
- Final report structure: `src/PatchPilot.Engine/Private/Invoke-Phase11.ps1:254-316`

---

## Standards Evidence Map

Phase11 automatically generates a `standardsEvidenceMap` in `final-report.json` that maps artifacts to compliance controls.

**[evidence]** `Invoke-Phase11.ps1:318-420`

```powershell
function New-StandardsEvidenceMap {
    param([hashtable]$Context)

    $Map = @{
        'NIST SP 800-40r4' = @{
            url = 'https://csrc.nist.gov/publications/detail/sp/800-40/rev-4/final'
            phases = @{
                Plan = @{ evidence = @("Reports\pre-validation.json", "baseline.json") }
                Assess = @{ evidence = @("catalog.json", "pre-validation.json") }
                Deploy = @{ evidence = @('install-summary.jsonl', 'Events.jsonl') }
                Verify = @{ evidence = @("snapshot.json", "post-validation.json", "regressions.json") }
            }
        }
        'NIST 800-53r5' = @{ ... }
        'CIS Controls v8' = @{ ... }
    }
    return $Map
}
```

---

## NIST SP 800-40r4 (Patch Management)

### Overview

NIST SP 800-40 Revision 4 defines enterprise patch management processes. PatchPilot's 11-phase pipeline maps directly to the four lifecycle phases.

### Phase Mapping

| NIST 800-40r4 Phase | Description | PatchPilot Phase(s) | Evidence Artifacts |
|---------------------|-------------|---------------------|-------------------|
| **Plan** | Prepare for patching operations | Phase01, Phase02 | `baseline.json`, `state.json` |
| **Assess** | Identify applicable patches and impact | Phase03, Phase04 | `catalog.json`, `pre-validation.json` |
| **Deploy** | Apply patches | Phase05 | `install-summary.jsonl`, `Events.jsonl` |
| **Verify** | Confirm patch success and system health | Phase07, Phase08, Phase11 | `snapshot.json`, `post-validation.json`, `regressions.json`, `final-report.json` |

### Evidence Details

#### Plan Phase

| Requirement | PatchPilot Evidence | Artifact Path |
|-------------|---------------------|---------------|
| Document baseline state | Pre-patch system snapshot | `Artifacts\Baseline\<RunId>\baseline.json` |
| Identify critical applications | Validation policy | `AppValidationPolicy.json` (config) |
| Define rollback procedures | Baseline for comparison | `Artifacts\Baseline\<RunId>\baseline.json` |

#### Assess Phase

| Requirement | PatchPilot Evidence | Artifact Path |
|-------------|---------------------|---------------|
| Identify available patches | Windows Update catalog | `Artifacts\UpdateCatalog\<RunId>\catalog.json` |
| Assess patch applicability | Classification filtering | `catalog.json` + `UpdatePolicy.json` |
| Test in pre-production | Pre-validation checks | `Reports\pre-validation.json` |

#### Deploy Phase

| Requirement | PatchPilot Evidence | Artifact Path |
|-------------|---------------------|---------------|
| Install patches | Per-update outcomes | `Logs\install-summary.jsonl` |
| Record install status | HRESULT codes, timing | `install-summary.jsonl` (per line) |
| Track reboot requirements | rebootRequired field | `install-summary.jsonl`, `reboot-required.json` |
| Maintain audit trail | Hash-chained events | `Logs\Events.jsonl` |

#### Verify Phase

| Requirement | PatchPilot Evidence | Artifact Path |
|-------------|---------------------|---------------|
| Confirm patch installation | Post-patch snapshot | `Artifacts\Snapshot\<RunId>\snapshot.json` |
| Verify system functionality | Post-validation | `Reports\post-validation.json` |
| Detect regressions | Pre/post comparison | `Reports\regressions.json` |
| Document outcomes | Comprehensive report | `Reports\final-report.json` |

---

## NIST 800-53r5 (Security Controls)

### Applicable Controls

| Control | Control Name | PatchPilot Coverage |
|---------|--------------|---------------------|
| **SI-2** | Flaw Remediation | Primary focus |
| **RA-5** | Vulnerability Monitoring and Scanning | Catalog and baseline |
| **CM-2** | Baseline Configuration | Snapshot artifacts |
| **CM-3** | Configuration Change Control | Diff report and events |
| **AU-2** | Event Logging | Events.jsonl |
| **AU-3** | Content of Audit Records | Structured event schema |
| **AU-6** | Audit Record Review, Analysis, and Reporting | Final report |
| **AU-9** | Protection of Audit Information | Hash chains, Merkle roots |
| **AU-10** | Non-Repudiation | Cryptographic integrity |

### Control Evidence Mapping

#### SI-2: Flaw Remediation

| Requirement | Evidence | Notes |
|-------------|----------|-------|
| Identify flaws | `catalog.json` | Available updates from Windows Update |
| Remediate flaws | `install-summary.jsonl` | Per-update outcomes with HRESULT |
| Test remediation | `pre/post-validation.json` | Application health checks |
| Prioritize remediation | `UpdatePolicy.json` | Classification filtering |

**Artifacts:**
```
Artifacts\UpdateCatalog\<RunId>\catalog.json
Logs\install-summary.jsonl
Reports\pre-validation.json
Reports\post-validation.json
```

#### RA-5: Vulnerability Monitoring and Scanning

| Requirement | Evidence | Notes |
|-------------|----------|-------|
| Monitor vulnerabilities | `catalog.json` | Pending security updates |
| System inventory | `baseline.json` | Services, drivers, apps |
| Track remediation | `install-summary.jsonl` | Which KBs installed |

**Artifacts:**
```
Artifacts\Baseline\<RunId>\baseline.json
Artifacts\UpdateCatalog\<RunId>\catalog.json
```

#### CM-2: Baseline Configuration

| Requirement | Evidence | Notes |
|-------------|----------|-------|
| Document baseline | `baseline.json` | Pre-patch state |
| Maintain currency | `snapshot.json` | Post-patch state |
| Review baseline changes | `diff-report.json` | Computed differences |

**Artifacts:**
```
Artifacts\Baseline\<RunId>\baseline.json
Artifacts\Snapshot\<RunId>\snapshot.json
Reports\diff-report.json
```

#### CM-3: Configuration Change Control

| Requirement | Evidence | Notes |
|-------------|----------|-------|
| Audit changes | `Events.jsonl` | Hash-chained timeline |
| Document changes | `diff-report.json` | What changed |
| Review changes | `final-report.json` | Summary of all changes |
| Integrity protection | `manifest.json` | Merkle root over artifacts |

**Artifacts:**
```
Logs\Events.jsonl
Reports\diff-report.json
manifest.json
```

#### AU-9: Protection of Audit Information

| Requirement | Evidence | Notes |
|-------------|----------|-------|
| Protect audit logs | Hash chaining | `prevHash` in each event |
| Detect tampering | Merkle root | `manifest.merkleRoot` |
| Prevent deletion | Events are append-only | New events don't modify old |

**Verification Script:**
```powershell
# Verify event chain integrity
$lines = Get-Content 'Logs\Events.jsonl'
$sha = [System.Security.Cryptography.SHA256]::Create()
for ($i = 1; $i -lt $lines.Count; $i++) {
    $expected = [BitConverter]::ToString($sha.ComputeHash(
        [Text.Encoding]::UTF8.GetBytes($lines[$i-1])
    )).Replace('-','').ToLower()
    $actual = ($lines[$i] | ConvertFrom-Json).prevHash
    if ($expected -ne $actual) {
        throw "Chain broken at line $i"
    }
}
```

---

## CIS Controls v8

### Applicable Controls

| Control | Control Name | PatchPilot Coverage |
|---------|--------------|---------------------|
| **7.1** | Establish and Maintain a Vulnerability Management Process | Full lifecycle |
| **7.2** | Establish and Maintain a Remediation Process | Phases 03-06 |
| **7.3** | Perform Automated Operating System Patch Management | Core function |
| **7.4** | Perform Automated Application Patch Management | Via catalog |
| **12.1** | Ensure Network Infrastructure is Up-to-Date | Driver/service baseline |
| **16.1** | Establish and Maintain a Secure Application Development Process | Validation patterns |

### Control Evidence Mapping

#### Control 7: Continuous Vulnerability Management

| Sub-Control | PatchPilot Evidence | Artifact |
|-------------|---------------------|----------|
| 7.1 Vuln management process | Automated pipeline | `Events.jsonl` (full timeline) |
| 7.2 Remediation process | Phase05 install | `install-summary.jsonl` |
| 7.3 OS patch management | Windows Update integration | `catalog.json`, `install-summary.jsonl` |
| 7.4 App patch management | Catalog classification | `catalog.json` |
| 7.7 Remediation verification | Post-validation | `post-validation.json`, `regressions.json` |

#### Control 12: Network Infrastructure Management

| Sub-Control | PatchPilot Evidence | Artifact |
|-------------|---------------------|----------|
| 12.1 Up-to-date infrastructure | Baseline/snapshot comparison | `baseline.json`, `snapshot.json` |
| Driver inventory | Driver list in snapshot | `baseline.json` (drivers section) |
| Service state | Service status capture | `baseline.json` (services section) |

#### Control 16: Application Software Security

| Sub-Control | PatchPilot Evidence | Artifact |
|-------------|---------------------|----------|
| 16.12 Application health monitoring | Validation patterns | `pre/post-validation.json` |
| 16.13 Regression detection | Pre/post comparison | `regressions.json` |
| Health endpoints | HTTP checks | `AppValidationPolicy.json` |
| Synthetic tests | Command execution | `AppValidationPolicy.json` |

---

## Evidence Collection Quick Reference

### For SI-2 (Flaw Remediation) Audit

```powershell
# Collect SI-2 evidence package
$RunId = '<your-run-id>'
$RunRoot = "C:\PatchPilot\Output\Runs\$RunId"

$SI2Evidence = @{
    catalog = Join-Path $RunRoot "Artifacts\UpdateCatalog\$RunId\catalog.json"
    installSummary = Join-Path $RunRoot 'Logs\install-summary.jsonl'
    preValidation = Join-Path $RunRoot 'Reports\pre-validation.json'
    postValidation = Join-Path $RunRoot 'Reports\post-validation.json'
    regressions = Join-Path $RunRoot 'Reports\regressions.json'
    manifest = Join-Path $RunRoot 'manifest.json'
}

# Package for auditor
$SI2Evidence.Values | ForEach-Object { Copy-Item $_ -Destination '.\SI2-Evidence\' }
Compress-Archive -Path '.\SI2-Evidence\*' -DestinationPath "SI2-Evidence-$RunId.zip"
```

### For CM-2/CM-3 (Configuration Management) Audit

```powershell
# Collect CM evidence
$CMEvidence = @{
    baseline = Join-Path $RunRoot "Artifacts\Baseline\$RunId\baseline.json"
    snapshot = Join-Path $RunRoot "Artifacts\Snapshot\$RunId\snapshot.json"
    diffReport = Join-Path $RunRoot 'Reports\diff-report.json'
    events = Join-Path $RunRoot 'Logs\Events.jsonl'
    manifest = Join-Path $RunRoot 'manifest.json'
}
```

### For CIS Control 7 Audit

```powershell
# Collect Control 7 evidence
$C7Evidence = @{
    catalog = Join-Path $RunRoot "Artifacts\UpdateCatalog\$RunId\catalog.json"
    installSummary = Join-Path $RunRoot 'Logs\install-summary.jsonl'
    regressions = Join-Path $RunRoot 'Reports\regressions.json'
    finalReport = Join-Path $RunRoot 'Reports\final-report.json'
}
```

---

## StandardsEvidenceMap in Final Report

### Structure

The `standardsEvidenceMap` in `final-report.json` provides machine-readable evidence paths:

```json
{
  "standardsEvidenceMap": {
    "NIST SP 800-40r4": {
      "url": "https://csrc.nist.gov/publications/detail/sp/800-40/rev-4/final",
      "phases": {
        "Plan": {
          "description": "Planning and preparation for patch management",
          "evidence": [
            "Reports\\pre-validation.json",
            "Artifacts\\Baseline\\abc123...\\baseline.json"
          ]
        },
        "Assess": {
          "description": "Assessment of applicable updates and impact",
          "evidence": [
            "Artifacts\\UpdateCatalog\\abc123...\\catalog.json",
            "Reports\\pre-validation.json"
          ]
        },
        "Deploy": {
          "description": "Deployment of patches",
          "evidence": [
            "Logs\\install-summary.jsonl",
            "Logs\\Events.jsonl"
          ]
        },
        "Verify": {
          "description": "Post-deployment verification",
          "evidence": [
            "Artifacts\\Snapshot\\abc123...\\snapshot.json",
            "Reports\\post-validation.json",
            "Reports\\regressions.json",
            "Reports\\diff-report.json"
          ]
        }
      }
    },
    "NIST 800-53r5": {
      "url": "https://csrc.nist.gov/publications/detail/sp/800-53/rev-5/final",
      "controls": {
        "SI-2": {
          "description": "Flaw Remediation",
          "evidence": [
            "Logs\\install-summary.jsonl",
            "Artifacts\\UpdateCatalog\\abc123...\\catalog.json"
          ]
        },
        "RA-5": {
          "description": "Vulnerability Monitoring and Scanning",
          "evidence": [
            "Artifacts\\Baseline\\abc123...\\baseline.json",
            "Artifacts\\UpdateCatalog\\abc123...\\catalog.json"
          ]
        },
        "CM-2": {
          "description": "Baseline Configuration",
          "evidence": [
            "Artifacts\\Baseline\\abc123...\\baseline.json",
            "artifact-index.json"
          ]
        },
        "CM-3": {
          "description": "Configuration Change Control",
          "evidence": [
            "Reports\\diff-report.json",
            "Logs\\Events.jsonl",
            "manifest.json"
          ]
        }
      }
    },
    "CIS Controls v8": {
      "url": "https://www.cisecurity.org/controls/v8",
      "controls": {
        "Control 7": {
          "description": "Continuous Vulnerability Management",
          "evidence": [
            "Artifacts\\UpdateCatalog\\abc123...\\catalog.json",
            "Logs\\install-summary.jsonl"
          ]
        },
        "Control 12": {
          "description": "Network Infrastructure Management",
          "evidence": [
            "Artifacts\\Baseline\\abc123...\\baseline.json",
            "Artifacts\\Snapshot\\abc123...\\snapshot.json"
          ]
        },
        "Control 16": {
          "description": "Application Software Security",
          "evidence": [
            "Reports\\pre-validation.json",
            "Reports\\post-validation.json",
            "Reports\\regressions.json"
          ]
        }
      }
    }
  }
}
```

---

## Auditor FAQ

### Q: How do I prove KB5012345 was installed on device X?

```powershell
$RunRoot = 'C:\PatchPilot\Output\Runs\<RunId>'
$InstallSummary = Get-Content (Join-Path $RunRoot 'Logs\install-summary.jsonl') |
    ForEach-Object { $_ | ConvertFrom-Json }

$KB = $InstallSummary | Where-Object { $_.kb -eq 'KB5012345' }
if ($KB) {
    Write-Output "KB5012345 installed: $($KB.installed)"
    Write-Output "HRESULT: $($KB.hresult)"
    Write-Output "Timestamp: Check Events.jsonl for PatchInstallEnd"
}
```

### Q: How do I verify the evidence hasn't been tampered with?

1. Verify event chain:
   ```powershell
   # Run hash chain verification (see Security-Model-and-Redaction.md)
   ```

2. Verify Merkle root:
   ```powershell
   $Manifest = Get-Content 'manifest.json' -Raw | ConvertFrom-Json
   # Recompute Merkle root from artifact-index.json and compare
   ```

### Q: What evidence proves no regressions occurred?

```powershell
$Regressions = Get-Content 'Reports\regressions.json' -Raw | ConvertFrom-Json
if ($Regressions.TotalRegressions -eq 0) {
    Write-Output "No regressions detected"
    Write-Output "Pre-validation passed: $(Test-Path 'Reports\pre-validation.json')"
    Write-Output "Post-validation passed: $(Test-Path 'Reports\post-validation.json')"
}
```

---

## See Also

- [Audit Playbook](Audit-Playbook.md) - Step-by-step audit procedures
- [Security Model & Redaction](Security-Model-and-Redaction.md) - Evidence integrity
- [Data Retention](Data-Retention.md) - Retention requirements
- [Evidence Verification](../OPERATIONS/Evidence-Verification.md) - Verification procedures
- [Artifacts & Schemas](../API/Artifacts-and-Schemas.md) - Complete artifact reference
