# Evidence-First Design

## Core Principle

**Evidence-First** means all decisions and outcomes derive from persisted artifacts on disk, never from in-memory state.

This principle ensures:
- **Auditability**: Every decision can be traced to a specific artifact
- **Reproducibility**: Exit codes are deterministic from evidence
- **Testability**: Tests can verify outcomes by reading files
- **Resilience**: Reboots don't lose state; resume is safe

## Why Evidence-First Matters

### Problem: In-Memory State is Ephemeral

Traditional patch scripts accumulate state in variables:
```powershell
# Anti-pattern: state lives in memory
$installedUpdates = @()
foreach ($update in $updates) {
    $result = Install-Update $update
    $installedUpdates += $result
}
# What happens if the system reboots here?
# What if you need to audit this run 3 months later?
```

**Issues:**
- Reboots lose all state
- No audit trail
- Exit codes are arbitrary ("I think it succeeded")
- Tests can't verify outcomes without mocking

### Solution: Persist Everything

```powershell
# Evidence-First pattern
foreach ($update in $updates) {
    $result = Install-Update $update
    # IMMEDIATELY persist to disk
    $result | ConvertTo-Json -Compress |
        Add-Content -Path 'Logs\install-summary.jsonl' -Encoding utf8NoBOM
}

# Later: derive exit code by re-reading evidence
$installRecords = Get-Content 'Logs\install-summary.jsonl' |
    ForEach-Object { $_ | ConvertFrom-Json }
$failures = $installRecords | Where-Object { -not $_.installed }
if ($failures) { return 210 }
```

**Benefits:**
- Survives reboots (read from disk on resume)
- Auditable (files persist for compliance review)
- Testable (tests read files, not mocks)
- Deterministic (same artifacts always → same exit code)

## Implementation in PatchPilot

### Exit Code Determination

**Location:** `Invoke-PatchPilotRun.ps1` lines 249-301

Exit codes are computed by **re-reading** persisted evidence:

```powershell
# 1) Check regressions.json (priority 1: exit 220)
$regressionsPath = Join-Path $context.OutputRoot "Reports\$($context.RunId)\regressions.json"
if (Test-Path $regressionsPath) {
    $regressionsReport = Get-Content $regressionsPath -Raw | ConvertFrom-Json
    if ($regressionsReport.TotalRegressions -gt 0) {
        return 220
    }
}

# 2) Check install-summary.jsonl (priority 2: exit 210)
$installSummaryPath = Join-Path $context.OutputRoot 'Logs\install-summary.jsonl'
if (Test-Path $installSummaryPath) {
    $installRecords = Get-Content $installSummaryPath | ForEach-Object { $_ | ConvertFrom-Json }
    if ($installRecords | Where-Object { -not $_.installed }) {
        return 210
    }
}

# 3) Check rebootRequired (priority 3: exit 150)
# ... (reads install-summary.jsonl again)

# 4) Check final-report.json (priority 4: exit 240)
# ...

# 5) Success (priority 5: exit 0)
return 0
```

**Key Point:** The engine does NOT track exit codes in variables. It reads files.

### Phase05 (Install) Persistence

**Location:** `Invoke-Phase05.ps1` lines 68-110 (inferred from usage)

Every update appends a JSONL line **immediately** after install:

```powershell
foreach ($update in $updates) {
    $installStart = Get-Date

    # Emit event (persisted to Events.jsonl)
    New-EventRecord -Context $Context -Event 'PatchInstallStart' -Data @{
        kb = $update.kb
        title = $update.title
    }

    # Install update
    $result = Install-UpdateViaCOM $update  # (simplified)

    # Persist install outcome IMMEDIATELY
    $installRecord = @{
        kb = $update.kb
        title = $update.title
        classification = $update.classification
        downloaded = $result.Downloaded
        installed = $result.Installed
        hresult = $result.HResult
        rebootRequired = $result.RebootRequired
        durationMs = ((Get-Date) - $installStart).TotalMilliseconds
    }

    $installRecord | ConvertTo-Json -Compress |
        Add-Content -Path $installSummaryPath -Encoding utf8NoBOM
}
```

**No in-memory aggregation.** Phase05 doesn't return a "success" boolean. Later phases read `install-summary.jsonl` from disk.

### TestMode Validation

**Location:** `Invoke-PatchPilotRun.ps1` lines 79-121

TestMode demonstrates evidence-first by **mutating artifacts on disk**, then computing exit code:

```powershell
if ($TestMode.IsPresent) {
    # 1) Run Phase02 (baseline) and Phase04 (pre-validation) normally
    Invoke-Phase02 -Context $context
    Invoke-Phase04 -Context $context

    # 2) Inject benign install evidence (on disk, not in memory)
    $installSummaryPath = Join-Path $context.OutputRoot 'Logs\install-summary.jsonl'
    '[{"kb":"N/A","title":"NoOp","...,"installed":true,...}]' |
        Set-Content -Path $installSummaryPath -Encoding utf8NoBOM

    # 3) Mutate AppValidationPolicy.json (on disk) to force POST regression
    $pol = Get-Content $policyPath -Raw | ConvertFrom-Json
    # ... modify patterns to fail ...
    $pol | ConvertTo-Json -Depth 10 | Set-Content -Path $policyPath -Encoding utf8NoBOM

    # 4) Re-run Phase08 (post-validation)
    #    Phase08 reads AppValidationPolicy.json from disk (sees mutated version)
    #    Phase08 writes regressions.json to disk
    Invoke-Phase08 -Context $context

    # 5) Compute exit code by reading regressions.json (evidence-first)
    $exit = Get-PatchPilotExitCodeFromEvidence -Context $context
    return $exit
}
```

This proves:
- Exit code is **not** determined by in-memory "success" flags
- Exit code is **computed** by reading artifacts
- Tests can mutate artifacts and verify behavior

### Reporting from Evidence

**Location:** `Invoke-Phase11.ps1` (inferred from design)

Phase11 builds `final-report.json` by reading ALL artifacts from disk:

```powershell
# Pseudocode (actual implementation in Private\Invoke-Phase11.ps1)
function Invoke-Phase11 {
    param([hashtable]$Context)

    # Read install summary
    $installSummaryPath = Join-Path $Context.OutputRoot 'Logs\install-summary.jsonl'
    $installRecords = Get-Content $installSummaryPath | ForEach-Object { ConvertFrom-Json $_ }

    # Read baseline and snapshot
    $baselinePath = Join-Path $Context.OutputRoot "Artifacts\Baseline\$($Context.RunId)\baseline.json"
    $snapshotPath = Join-Path $Context.OutputRoot "Artifacts\Snapshot\$($Context.RunId)\snapshot.json"
    $baseline = Get-Content $baselinePath -Raw | ConvertFrom-Json
    $snapshot = Get-Content $snapshotPath -Raw | ConvertFrom-Json

    # Read validation reports
    $preValidPath = Join-Path $Context.OutputRoot "Reports\$($Context.RunId)\pre-validation.json"
    $postValidPath = Join-Path $Context.OutputRoot "Reports\$($Context.RunId)\post-validation.json"
    $regressionsPath = Join-Path $Context.OutputRoot "Reports\$($Context.RunId)\regressions.json"

    # Read manifest
    $manifestPath = Join-Path $Context.OutputRoot "manifest.json"
    $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json

    # Build final report (no in-memory inference)
    $finalReport = @{
        runId = $Context.RunId
        installSummary = $installRecords
        validation = @{
            pre = (Get-Content $preValidPath -Raw | ConvertFrom-Json)
            post = (Get-Content $postValidPath -Raw | ConvertFrom-Json)
            regressions = (Get-Content $regressionsPath -Raw | ConvertFrom-Json)
        }
        systemDiff = Compare-Snapshots $baseline $snapshot
        integrity = @{
            merkleRoot = $manifest.merkleRoot
            eventsChainHead = $manifest.eventsChainHead
        }
    }

    # Write to disk
    $finalReport | ConvertTo-Json -Depth 10 |
        Set-Content -Path "Reports\$($Context.RunId)\final-report.json" -Encoding utf8NoBOM
}
```

**No shortcuts.** The report is built entirely from persisted files.

## Evidence Integrity

### Hash Chaining (Events.jsonl)

**Implementation:** `New-EventRecord` (in `src/PatchPilot.Engine/Private/New-EventRecord.ps1`)

Each event includes `prevHash` field (SHA-256 of previous event's JSON):

```powershell
function New-EventRecord {
    param($Context, $Event, $Level, $Data)

    $eventsPath = Join-Path $Context.OutputRoot 'Logs\Events.jsonl'

    # Read previous event to get its hash
    $prevHash = ""
    if (Test-Path $eventsPath) {
        $lastLine = Get-Content $eventsPath -Tail 1
        $lastEvent = $lastLine | ConvertFrom-Json
        $prevHash = (Get-FileHash -InputStream ([IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes($lastLine))) -Algorithm SHA256).Hash.ToLower()
    }

    # Build new event
    $eventRecord = @{
        timestamp = (Get-Date).ToUniversalTime().ToString('o')
        runId = $Context.RunId
        event = $Event
        level = $Level
        prevHash = $prevHash
        data = $Data
    } | ConvertTo-Json -Compress

    # Append to JSONL
    Add-Content -Path $eventsPath -Value $eventRecord -Encoding utf8NoBOM
}
```

**Result:** Tampering with any event breaks the chain (can be detected).

### Merkle Root (Artifacts)

**Implementation:** `Write-Manifest` (in `src/PatchPilot.Engine/Private/Write-Manifest.ps1`)

Computes Merkle tree root over all artifact SHA-256 hashes:

```powershell
function Write-Manifest {
    param([hashtable]$Context)

    # Read artifact index (built by New-ArtifactIndex)
    $indexPath = Join-Path $Context.OutputRoot 'artifact-index.json'
    $index = Get-Content $indexPath -Raw | ConvertFrom-Json

    # Extract SHA-256 hashes
    $hashes = $index | ForEach-Object { $_.sha256 }

    # Compute Merkle root (simplified: hash concatenation of sorted hashes)
    $sortedHashes = $hashes | Sort-Object
    $concatenated = $sortedHashes -join ''
    $merkleRoot = (Get-FileHash -InputStream ([IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes($concatenated))) -Algorithm SHA256).Hash.ToLower()

    # Read final event hash (eventsChainHead)
    $eventsPath = Join-Path $Context.OutputRoot 'Logs\Events.jsonl'
    $lastEvent = Get-Content $eventsPath -Tail 1
    $eventsChainHead = (Get-FileHash -InputStream ([IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes($lastEvent))) -Algorithm SHA256).Hash.ToLower()

    # Write manifest
    $manifest = @{
        runId = $Context.RunId
        merkleRoot = $merkleRoot
        artifactCount = $index.Count
        eventsChainHead = $eventsChainHead
        timestamp = (Get-Date).ToUniversalTime().ToString('o')
        tenantId = $Context.TenantId
        clientId = $Context.ClientId
        deviceId = $Context.DeviceId
    }

    $manifest | ConvertTo-Json | Set-Content -Path (Join-Path $Context.OutputRoot 'manifest.json') -Encoding utf8NoBOM
}
```

**Verification:** `manifest.json` allows auditors to verify artifact integrity offline.

## Testing Evidence-First

**Example:** `tests/StageF.Tests.ps1` (lines 79-85)

Tests verify outcomes by reading artifacts:

```powershell
It 'Should create regressions.json' {
    $regressionsPath = Get-ChildItem -Path $script:testOutputRoot -Recurse -Filter 'regressions.json' | Select-Object -First 1
    $regressionsPath | Should -Not -BeNullOrEmpty
}

It 'Should detect regressions in TestMode' {
    $regressionsPath = Get-ChildItem -Path $script:testOutputRoot -Recurse -Filter 'regressions.json' | Select-Object -First 1
    $regressions = Get-Content $regressionsPath.FullName -Raw | ConvertFrom-Json
    $regressions.TotalRegressions | Should -BeGreaterThan 0
}
```

Tests don't mock. They read real files.

## Summary

| Principle | Implementation | Benefit |
|-----------|----------------|---------|
| Persist immediately | JSONL append after each update | Survives reboots |
| Re-read for decisions | Exit codes computed from files | Deterministic |
| No in-memory aggregation | Phase11 reads all artifacts | Auditable |
| Hash chains | `prevHash` in Events.jsonl | Tamper-evident |
| Merkle roots | `merkleRoot` in manifest.json | Integrity verification |

**Evidence-First is not optional.** It's the foundation of PatchPilot's auditability and compliance guarantees.

## References

- [Architecture Overview](Architecture.md)
- [Phases](Phases.md)
- [Compliance Mapping](../SECURITY-COMPLIANCE/Compliance-Mapping.md)
- [Evidence Verification](../OPERATIONS/Evidence-Verification.md)
