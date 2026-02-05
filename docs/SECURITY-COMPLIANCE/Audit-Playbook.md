# Audit Playbook

## Overview

This playbook provides step-by-step procedures for conducting compliance audits using PatchPilot evidence artifacts. It covers preparation, evidence collection, verification, and reporting for common audit scenarios.

**Referenced Code:**
- Standards evidence map: `src/PatchPilot.Engine/Private/Invoke-Phase11.ps1:318-420`
- Hash chain verification: `src/PatchPilot.Engine/Private/New-EventRecord.ps1`
- Merkle root: `src/PatchPilot.Engine/Private/Write-Manifest.ps1:74-111`

---

## Audit Types Supported

| Audit Type | Primary Artifacts | PatchPilot Support |
|------------|-------------------|-------------------|
| SOC 2 Type II | Patch evidence, change logs | Full |
| ISO 27001 | Security control evidence | Full |
| NIST 800-53 | SI-2, RA-5, CM-2, CM-3, AU-* | Full |
| NIST 800-40r4 | Plan/Assess/Deploy/Verify | Full |
| CIS Controls v8 | Control 7, 12, 16 | Full |
| HIPAA Security Rule | Technical safeguards | Partial |
| PCI DSS | Req 6.3 (patching) | Partial |

---

## Pre-Audit Preparation

### 1. Identify Audit Scope

Before beginning, clarify:
- **Time period:** Which runs are in scope?
- **Systems:** Which devices/clients are included?
- **Controls:** Which specific controls are being audited?
- **Evidence format:** Paper/PDF vs. live system access

### 2. Locate Evidence Roots

```powershell
# Typical evidence locations
$OutputRoot = 'C:\PatchPilot\Output'
$RunsRoot = Join-Path $OutputRoot 'Runs'

# List all runs in scope period
$StartDate = [datetime]'2026-01-01'
$EndDate = [datetime]'2026-01-31'

Get-ChildItem -Path $RunsRoot -Directory | ForEach-Object {
    $RunJson = Join-Path $_.FullName 'run.json'
    if (Test-Path $RunJson) {
        $Run = Get-Content $RunJson | ConvertFrom-Json
        $EndTime = [datetime]$Run.endTimeUtc
        if ($EndTime -ge $StartDate -and $EndTime -le $EndDate) {
            [PSCustomObject]@{
                RunId = $Run.runId
                Device = $Run.deviceId
                Client = $Run.clientId
                EndTime = $EndTime
                ExitCode = $Run.exitCode
                Path = $_.FullName
            }
        }
    }
} | Format-Table
```

### 3. Verify Evidence Integrity

Before presenting evidence to auditors, verify cryptographic integrity:

```powershell
function Test-RunIntegrity {
    param([string]$RunRoot)

    $Results = @{
        RunRoot = $RunRoot
        HashChainValid = $false
        MerkleRootValid = $false
        ChainHeadValid = $false
    }

    # 1. Verify hash chain
    $EventsPath = Join-Path $RunRoot 'Logs\Events.jsonl'
    if (Test-Path $EventsPath) {
        $Lines = Get-Content $EventsPath
        $Sha256 = [System.Security.Cryptography.SHA256]::Create()
        $ChainValid = $true

        for ($i = 1; $i -lt $Lines.Count; $i++) {
            $PrevHash = [BitConverter]::ToString(
                $Sha256.ComputeHash([Text.Encoding]::UTF8.GetBytes($Lines[$i-1]))
            ).Replace('-','').ToLower()
            $Current = $Lines[$i] | ConvertFrom-Json
            if ($Current.prevHash -ne $PrevHash) {
                $ChainValid = $false
                break
            }
        }
        $Results.HashChainValid = $ChainValid
    }

    # 2. Verify Merkle root
    $ManifestPath = Join-Path $RunRoot 'manifest.json'
    $IndexPath = Join-Path $RunRoot 'artifact-index.json'
    if ((Test-Path $ManifestPath) -and (Test-Path $IndexPath)) {
        $Manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json
        $Index = Get-Content $IndexPath -Raw | ConvertFrom-Json
        $Hashes = $Index | ForEach-Object { $_.sha256 } | Sort-Object
        $ComputedRoot = Get-MerkleRoot -Hashes $Hashes
        $Results.MerkleRootValid = ($ComputedRoot -eq $Manifest.merkleRoot)
    }

    # 3. Verify events chain head
    if ((Test-Path $EventsPath) -and (Test-Path $ManifestPath)) {
        $LastLine = Get-Content $EventsPath | Select-Object -Last 1
        $HashAlg = [System.Security.Cryptography.SHA256]::Create()
        $ComputedHead = [BitConverter]::ToString(
            $HashAlg.ComputeHash([Text.Encoding]::UTF8.GetBytes($LastLine))
        ).Replace('-','').ToLower()
        $Results.ChainHeadValid = ($ComputedHead -eq $Manifest.eventsChainHead)
    }

    return $Results
}

# Usage
$Integrity = Test-RunIntegrity -RunRoot 'C:\PatchPilot\Output\Runs\abc123-...'
$Integrity
```

---

## NIST 800-40r4 Audit Playbook

NIST SP 800-40r4 defines four phases: Plan, Assess, Deploy, Verify.

### Step 1: Gather Phase Evidence

```powershell
$RunRoot = 'C:\PatchPilot\Output\Runs\abc123-...'
$RunId = Split-Path $RunRoot -Leaf

$NIST80040Evidence = @{
    Plan = @{
        baseline = Join-Path $RunRoot "Artifacts\Baseline\$RunId\baseline.json"
        preValidation = Join-Path $RunRoot 'Reports\pre-validation.json'
    }
    Assess = @{
        catalog = Join-Path $RunRoot "Artifacts\UpdateCatalog\$RunId\catalog.json"
        preValidation = Join-Path $RunRoot 'Reports\pre-validation.json'
    }
    Deploy = @{
        installSummary = Join-Path $RunRoot 'Logs\install-summary.jsonl'
        events = Join-Path $RunRoot 'Logs\Events.jsonl'
    }
    Verify = @{
        snapshot = Join-Path $RunRoot "Artifacts\Snapshot\$RunId\snapshot.json"
        postValidation = Join-Path $RunRoot 'Reports\post-validation.json'
        regressions = Join-Path $RunRoot 'Reports\regressions.json'
        diffReport = Join-Path $RunRoot 'Reports\diff-report.json'
    }
}
```

### Step 2: Verify Plan Phase Evidence

```powershell
# Verify baseline was captured before patching
$Baseline = Get-Content $NIST80040Evidence.Plan.baseline -Raw | ConvertFrom-Json
Write-Host "Baseline timestamp: $($Baseline.timestamp)"
Write-Host "Services captured: $($Baseline.services.Count)"
Write-Host "Drivers captured: $($Baseline.drivers.Count)"
```

### Step 3: Verify Assess Phase Evidence

```powershell
# Verify update catalog was retrieved
$Catalog = Get-Content $NIST80040Evidence.Assess.catalog -Raw | ConvertFrom-Json
Write-Host "Catalog timestamp: $($Catalog.timestamp)"
Write-Host "Updates available: $($Catalog.updateCount)"

# Verify pre-validation passed
$PreVal = Get-Content $NIST80040Evidence.Assess.preValidation -Raw | ConvertFrom-Json
Write-Host "Pre-validation checks: $($PreVal.applications.Count) apps"
```

### Step 4: Verify Deploy Phase Evidence

```powershell
# Verify patch installation outcomes
$InstallSummary = Get-Content $NIST80040Evidence.Deploy.installSummary |
    ForEach-Object { $_ | ConvertFrom-Json }

Write-Host "Updates processed: $($InstallSummary.Count)"
$Installed = $InstallSummary | Where-Object { $_.installed }
$Failed = $InstallSummary | Where-Object { -not $_.installed }
Write-Host "Successfully installed: $($Installed.Count)"
Write-Host "Failed: $($Failed.Count)"

# Show install events from timeline
$Events = Get-Content $NIST80040Evidence.Deploy.events |
    ForEach-Object { $_ | ConvertFrom-Json } |
    Where-Object { $_.event -match 'PatchInstall' }

$Events | Select-Object timestamp, event, @{N='kb';E={$_.data.kb}} | Format-Table
```

### Step 5: Verify Verify Phase Evidence

```powershell
# Check for regressions
$Regressions = Get-Content $NIST80040Evidence.Verify.regressions -Raw | ConvertFrom-Json
Write-Host "Regressions detected: $($Regressions.TotalRegressions)"

# Verify post-patch snapshot exists
$Snapshot = Get-Content $NIST80040Evidence.Verify.snapshot -Raw | ConvertFrom-Json
Write-Host "Snapshot timestamp: $($Snapshot.timestamp)"

# Show system changes
if (Test-Path $NIST80040Evidence.Verify.diffReport) {
    $Diff = Get-Content $NIST80040Evidence.Verify.diffReport -Raw | ConvertFrom-Json
    Write-Host "Services changed: $($Diff.servicesChanged.Count)"
}
```

### Step 6: Package Evidence

```powershell
$AuditPackage = "NIST-80040-Evidence-$(Get-Date -Format 'yyyyMMdd').zip"
$TempDir = New-Item -ItemType Directory -Path "$env:TEMP\NIST80040-$RunId" -Force

# Copy evidence files
$AllFiles = $NIST80040Evidence.Values | ForEach-Object { $_.Values }
$AllFiles | Where-Object { Test-Path $_ } | ForEach-Object {
    Copy-Item $_ -Destination $TempDir
}

# Include integrity proof
Copy-Item (Join-Path $RunRoot 'manifest.json') -Destination $TempDir
Copy-Item (Join-Path $RunRoot 'artifact-index.json') -Destination $TempDir

Compress-Archive -Path "$TempDir\*" -DestinationPath $AuditPackage
Write-Host "Evidence packaged: $AuditPackage"
```

---

## NIST 800-53r5 Audit Playbook

### SI-2 (Flaw Remediation)

**Control Requirement:** Identify, report, and correct system flaws.

```powershell
$RunRoot = 'C:\PatchPilot\Output\Runs\abc123-...'

# Evidence: Flaws identified (catalog)
$Catalog = Get-Content (Join-Path $RunRoot "Artifacts\UpdateCatalog\*\catalog.json") -Raw | ConvertFrom-Json
Write-Host "Flaws identified: $($Catalog.updateCount) pending updates"

# Evidence: Flaws remediated (install summary)
$Installs = Get-Content (Join-Path $RunRoot 'Logs\install-summary.jsonl') |
    ForEach-Object { $_ | ConvertFrom-Json }
$Remediated = $Installs | Where-Object { $_.installed }
Write-Host "Flaws remediated: $($Remediated.Count) updates installed"

# Evidence: Remediation tested (validation)
$PostVal = Get-Content (Join-Path $RunRoot 'Reports\post-validation.json') -Raw | ConvertFrom-Json
$PassedChecks = ($PostVal.applications | ForEach-Object { $_.checks | Where-Object { $_.success } }).Count
Write-Host "Remediation tested: $PassedChecks validation checks passed"
```

### CM-2 (Baseline Configuration)

**Control Requirement:** Develop, document, and maintain baseline configuration.

```powershell
# Evidence: Baseline documented
$Baseline = Get-Content (Join-Path $RunRoot "Artifacts\Baseline\*\baseline.json") -Raw | ConvertFrom-Json
Write-Host "Baseline documented at: $($Baseline.timestamp)"
Write-Host "Services: $($Baseline.services.Count)"
Write-Host "Drivers: $($Baseline.drivers.Count)"

# Evidence: Baseline maintained (post-patch snapshot)
$Snapshot = Get-Content (Join-Path $RunRoot "Artifacts\Snapshot\*\snapshot.json") -Raw | ConvertFrom-Json
Write-Host "Updated baseline at: $($Snapshot.timestamp)"
```

### CM-3 (Configuration Change Control)

**Control Requirement:** Audit configuration changes.

```powershell
# Evidence: Changes audited (diff report)
$Diff = Get-Content (Join-Path $RunRoot 'Reports\diff-report.json') -Raw | ConvertFrom-Json

# Evidence: Change timeline (hash-chained events)
$Events = Get-Content (Join-Path $RunRoot 'Logs\Events.jsonl') |
    ForEach-Object { $_ | ConvertFrom-Json }
Write-Host "Total events: $($Events.Count)"
Write-Host "Events with hash chain: All events linked via prevHash"

# Evidence: Integrity protection (Merkle root)
$Manifest = Get-Content (Join-Path $RunRoot 'manifest.json') -Raw | ConvertFrom-Json
Write-Host "Merkle root: $($Manifest.merkleRoot)"
```

### AU-9 (Protection of Audit Information)

**Control Requirement:** Protect audit information from unauthorized modification.

```powershell
# Evidence: Hash chain protects log integrity
Write-Host "Hash chaining: Each event in Events.jsonl contains prevHash field"
Write-Host "Merkle root: Computed over all artifact hashes"
Write-Host "Chain head: SHA-256 of final event stored in manifest"

# Demonstrate integrity verification
$Integrity = Test-RunIntegrity -RunRoot $RunRoot
Write-Host "Hash chain valid: $($Integrity.HashChainValid)"
Write-Host "Merkle root valid: $($Integrity.MerkleRootValid)"
Write-Host "Chain head valid: $($Integrity.ChainHeadValid)"
```

---

## CIS Controls v8 Audit Playbook

### Control 7 (Continuous Vulnerability Management)

```powershell
$RunRoot = 'C:\PatchPilot\Output\Runs\abc123-...'

# 7.1 - Vulnerability management process
Write-Host "=== 7.1 Vulnerability Management Process ==="
$Events = Get-Content (Join-Path $RunRoot 'Logs\Events.jsonl') | Select-Object -First 5
Write-Host "Automated pipeline timeline captured in Events.jsonl"

# 7.3 - OS patch management
Write-Host "`n=== 7.3 OS Patch Management ==="
$Catalog = Get-Content (Join-Path $RunRoot "Artifacts\UpdateCatalog\*\catalog.json") -Raw | ConvertFrom-Json
Write-Host "Updates identified: $($Catalog.updateCount)"

$Installs = Get-Content (Join-Path $RunRoot 'Logs\install-summary.jsonl') |
    ForEach-Object { $_ | ConvertFrom-Json }
Write-Host "Updates applied: $(($Installs | Where-Object {$_.installed}).Count)"

# 7.7 - Remediation verification
Write-Host "`n=== 7.7 Remediation Verification ==="
$Regressions = Get-Content (Join-Path $RunRoot 'Reports\regressions.json') -Raw | ConvertFrom-Json
Write-Host "Regressions detected: $($Regressions.TotalRegressions)"
$PostVal = Get-Content (Join-Path $RunRoot 'Reports\post-validation.json') -Raw | ConvertFrom-Json
Write-Host "Post-validation apps checked: $($PostVal.applications.Count)"
```

### Control 16 (Application Software Security)

```powershell
# 16.12 - Application health monitoring
Write-Host "=== 16.12 Application Health Monitoring ==="
$PreVal = Get-Content (Join-Path $RunRoot 'Reports\pre-validation.json') -Raw | ConvertFrom-Json
$PostVal = Get-Content (Join-Path $RunRoot 'Reports\post-validation.json') -Raw | ConvertFrom-Json
Write-Host "Pre-patch validation: $($PreVal.applications.Count) apps"
Write-Host "Post-patch validation: $($PostVal.applications.Count) apps"

# 16.13 - Regression detection
Write-Host "`n=== 16.13 Regression Detection ==="
$Regressions = Get-Content (Join-Path $RunRoot 'Reports\regressions.json') -Raw | ConvertFrom-Json
if ($Regressions.TotalRegressions -gt 0) {
    Write-Host "Regressions found:"
    $Regressions.Regressions | ForEach-Object {
        Write-Host "  - $($_.app): $($_.checkName) ($($_.preStatus) -> $($_.postStatus))"
    }
} else {
    Write-Host "No regressions detected"
}
```

---

## Evidence Package Templates

### Compliance Evidence Package

```powershell
function New-CompliancePackage {
    param(
        [string]$RunRoot,
        [string]$Standard,  # 'NIST-800-40', 'NIST-800-53', 'CIS-v8'
        [string]$OutputPath
    )

    $RunId = Split-Path $RunRoot -Leaf
    $TempDir = New-Item -ItemType Directory -Path "$env:TEMP\Compliance-$Standard-$RunId" -Force

    # Core evidence (always included)
    $CoreFiles = @(
        'manifest.json',
        'artifact-index.json',
        'run.json',
        'Logs\Events.jsonl',
        'Logs\install-summary.jsonl',
        'Reports\final-report.json',
        'Reports\regressions.json'
    )

    foreach ($File in $CoreFiles) {
        $Source = Join-Path $RunRoot $File
        if (Test-Path $Source) {
            $DestDir = Join-Path $TempDir (Split-Path $File -Parent)
            if (!(Test-Path $DestDir)) { New-Item -ItemType Directory -Path $DestDir -Force | Out-Null }
            Copy-Item $Source -Destination (Join-Path $TempDir $File)
        }
    }

    # Standard-specific evidence
    switch ($Standard) {
        'NIST-800-40' {
            Copy-Item (Join-Path $RunRoot "Artifacts\Baseline\$RunId") -Destination "$TempDir\Baseline" -Recurse -ErrorAction SilentlyContinue
            Copy-Item (Join-Path $RunRoot "Artifacts\Snapshot\$RunId") -Destination "$TempDir\Snapshot" -Recurse -ErrorAction SilentlyContinue
            Copy-Item (Join-Path $RunRoot "Artifacts\UpdateCatalog\$RunId") -Destination "$TempDir\UpdateCatalog" -Recurse -ErrorAction SilentlyContinue
        }
        'NIST-800-53' {
            Copy-Item (Join-Path $RunRoot 'Reports\diff-report.json') -Destination $TempDir -ErrorAction SilentlyContinue
            Copy-Item (Join-Path $RunRoot 'Reports\pre-validation.json') -Destination $TempDir -ErrorAction SilentlyContinue
            Copy-Item (Join-Path $RunRoot 'Reports\post-validation.json') -Destination $TempDir -ErrorAction SilentlyContinue
        }
        'CIS-v8' {
            Copy-Item (Join-Path $RunRoot 'Reports\pre-validation.json') -Destination $TempDir -ErrorAction SilentlyContinue
            Copy-Item (Join-Path $RunRoot 'Reports\post-validation.json') -Destination $TempDir -ErrorAction SilentlyContinue
        }
    }

    # Create integrity verification script
    $VerifyScript = @'
# Integrity Verification Script
# Run this to verify evidence has not been tampered with

$Manifest = Get-Content 'manifest.json' -Raw | ConvertFrom-Json
Write-Host "Run ID: $($Manifest.runId)"
Write-Host "Artifact count: $($Manifest.artifactCount)"
Write-Host "Merkle root: $($Manifest.merkleRoot)"
Write-Host "Events chain head: $($Manifest.eventsChainHead)"
Write-Host "Generated: $($Manifest.generatedAt)"
'@
    Set-Content -Path (Join-Path $TempDir 'Verify-Integrity.ps1') -Value $VerifyScript

    # Package
    if (!$OutputPath) {
        $OutputPath = "$Standard-Evidence-$RunId-$(Get-Date -Format 'yyyyMMdd').zip"
    }
    Compress-Archive -Path "$TempDir\*" -DestinationPath $OutputPath -Force

    Write-Host "Compliance package created: $OutputPath"
    return $OutputPath
}

# Usage
New-CompliancePackage -RunRoot 'C:\PatchPilot\Output\Runs\abc123-...' -Standard 'NIST-800-53'
```

---

## Auditor Verification Guide

### For External Auditors

Provide auditors with this verification checklist:

**1. Verify Hash Chain (Events.jsonl)**
```powershell
# Each event's prevHash should equal SHA256 of the previous event's JSON
# Genesis event (first line) has prevHash = ""
```

**2. Verify Merkle Root**
```powershell
# manifest.merkleRoot should match recomputed Merkle tree from artifact-index.json
```

**3. Verify Events Chain Head**
```powershell
# manifest.eventsChainHead should equal SHA256 of the last line in Events.jsonl
```

**4. Verify Artifact Hashes**
```powershell
# Each file listed in artifact-index.json should match its recorded SHA256
$Index = Get-Content 'artifact-index.json' | ConvertFrom-Json
foreach ($Entry in $Index) {
    $Hash = (Get-FileHash -Path $Entry.path -Algorithm SHA256).Hash.ToLower()
    if ($Hash -ne $Entry.sha256) {
        Write-Warning "Hash mismatch: $($Entry.path)"
    }
}
```

---

## Audit Checklist

### Pre-Audit

- [ ] Identify runs in audit scope
- [ ] Verify integrity of all evidence
- [ ] Check redaction-log.json for redacted fields
- [ ] Prepare compliance package per standard

### During Audit

- [ ] Demonstrate evidence chain of custody (hash chain)
- [ ] Show Merkle root verification
- [ ] Walk through phase timeline in Events.jsonl
- [ ] Explain exit code interpretation
- [ ] Provide artifact-to-control mapping

### Post-Audit

- [ ] Archive evidence packages
- [ ] Document any exceptions or findings
- [ ] Update retention schedule if needed

---

## See Also

- [Compliance Mapping](Compliance-Mapping.md) - Standards to artifact mapping
- [Security Model](Security-Model-and-Redaction.md) - Integrity mechanisms
- [Evidence Verification](../OPERATIONS/Evidence-Verification.md) - Verification procedures
- [Data Retention](Data-Retention.md) - Retention requirements
- [Output Artifact Reference](../API/Output-Artifact-Reference.md) - Complete artifact documentation
