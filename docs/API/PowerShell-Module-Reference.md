# PowerShell Module Reference

## Module: PatchPilot.Engine

**Location:** `src/PatchPilot.Engine/PatchPilot.Engine.psd1`

**PowerShell Version:** 7.0+

**Import:**
```powershell
Import-Module .\src\PatchPilot.Engine\PatchPilot.Engine.psd1
```

---

## Public Functions

### Invoke-PatchPilotRun

Entry cmdlet for PatchPilot patch orchestration engine.

**Location:** `src/PatchPilot.Engine/Public/Invoke-PatchPilotRun.ps1`

**Synopsis:**
Executes patch orchestration pipeline across 11 phases with evidence-based auditing.

**Parameter Sets:**

The cmdlet supports two parameter sets:

1. **Online** (default) - For production MSP environments
   - Requires `-TenantId` and `-ClientId`
   - Full Graph/AAD integration

2. **Offline** - For lab/testing scenarios
   - Requires `-TestMode` switch
   - TenantId and ClientId are optional (default to 'Offline')
   - Skips Graph/AAD calls

**Syntax:**
```powershell
# Online mode (production)
Invoke-PatchPilotRun
    [-OutputRoot <string>]
    -ConfigPath <string>
    -TenantId <string>
    -ClientId <string>
    [-SiteId <string>]
    [-DeviceId <string>]
    [<CommonParameters>]

# Offline mode (lab/testing)
Invoke-PatchPilotRun
    [-OutputRoot <string>]
    -ConfigPath <string>
    [-TenantId <string>]
    [-ClientId <string>]
    [-SiteId <string>]
    [-DeviceId <string>]
    -TestMode
    [<CommonParameters>]
```

**Parameters:**

| Parameter | Type | Mandatory (Online) | Mandatory (Offline) | Default | Description |
|-----------|------|-------------------|---------------------|---------|-------------|
| OutputRoot | string | No | No | - | Root directory for artifacts. If omitted, it must be supplied via `config.outputRoot`. Run folders are created as `Runs\<RunId>\` where `RunId` is a GUID |
| ConfigPath | string | Yes | Yes | - | Path to configuration file. Relative paths in config resolved against config directory |
| TenantId | string | Yes | No | 'Offline' | Multi-tenant identifier |
| ClientId | string | Yes | No | 'Offline' | Client identifier within tenant |
| SiteId | string | No | No | 'Default' | Site identifier |
| DeviceId | string | No | No | `$env:COMPUTERNAME` | Device identifier |
| TestMode | switch | - | Yes | - | Enable offline/lab mode |

**Returns:** `[int]` - Exit code (0, 100, 150, 170, 210, 220, 230, 240)

The exit code is written to the pipeline via `Write-Output`, so callers can capture it:
```powershell
$exitCode = Invoke-PatchPilotRun -ConfigPath '...' -TestMode
```

**Output Structure:**

Each run creates a run folder under `OutputRoot\Runs\<RunId>\`, where `RunId` is a GUID:

```
OutputRoot\
  Runs\
    <RunId>\                # Run folder (RunId GUID)
      Logs\
      Artifacts\
      Reports\
        regressions.json      # Always created
      Telemetry\
      State\
      run.json                # Run metadata including exit code
  State\
    Tenants\<TenantId>\Clients\<ClientId>\Sites\<SiteId>\Devices\<DeviceId>\
      lock.json               # Per-device concurrency lock
      reboot-required.json    # Reboot cookie (created only when needed)
```

**Example 1: Online Mode (Production)**
```powershell
$exitCode = Invoke-PatchPilotRun `
    -OutputRoot 'C:\PatchPilot\Output' `
    -ConfigPath 'C:\PatchPilot\Config\ClientProfile.json' `
    -TenantId 'MSP001' `
    -ClientId 'ACME' `
    -SiteId 'HQ' `
    -DeviceId 'WIN-SERVER01'

switch ($exitCode) {
    0   { Write-Output "Patch cycle completed successfully" }
    150 { Write-Output "Reboot required (deferred)" }
    170 { Write-Output "Concurrency lock detected" }
    210 { Write-Output "Install failure detected" }
    220 { Write-Output "Validation regression detected" }
    240 { Write-Output "Reporting failure" }
}
```

**Example 2: Offline Mode (Lab/Testing)**
```powershell
# Minimal invocation - uses config.outputRoot (or wrapper default when using ./src/PatchPilot.ps1)
$exitCode = Invoke-PatchPilotRun `
    -ConfigPath 'examples\configs\lab\NoOp.json' `
    -TestMode

# With explicit output location
$exitCode = Invoke-PatchPilotRun `
    -OutputRoot 'C:\Test\Output' `
    -ConfigPath 'examples\configs\ClientProfile.json' `
    -TestMode
```

**Example 3: Config with Relative Policy Paths**
```json
// ClientProfile.json
{
  "profileId": "TEST",
  "AppValidationPolicyPath": "policies\\AppValidationPolicy.json"
}
```
When `ConfigPath` is `C:\Config\ClientProfile.json`, the policy file is resolved to `C:\Config\policies\AppValidationPolicy.json`.

**Behavior:**

1. Resolves ConfigPath and validates it exists

2. Loads config and resolves relative policy paths (against config directory)

3. Creates output skeleton (`Runs\<RunId>\...`), where RunId is a GUID

4. Checks for per-device concurrency lock under
 `State\Tenants\<TenantId>\Clients\<ClientId>\Sites\<SiteId>\Devices\<DeviceId>\lock.json` → exit 170 if present

5. In offline mode, logs "skipping Graph/AAD"

6. Initializes RunContext

7. Checks for reboot cookie → resumes to Phase07 if present

8. Runs Phase01-Phase11 (or subset based on reboot state)

9. Computes exit code by re-reading persisted evidence

10. Writes `run.json` with run metadata

11. Removes the per-device lock in a `finally` block

**Early Failure Behavior:**

If validation fails (config not found, policy file missing), the cmdlet:

1. Creates output skeleton first

2. Writes `regressions.json` with `TotalRegressions: 0`

3. Writes `run.json` with error information

4. Returns exit code 240

**TestMode Behavior:**

When `-TestMode` is passed:

1. TenantId/ClientId default to 'Offline' if not specified

2. Skips Graph/AAD calls

3. Runs Phase02 (baseline) and Phase04 (pre-validation) normally

4. Injects benign `install-summary.jsonl` (no real updates)

5. Mutates `AppValidationPolicy.json` to force POST failures

6. Runs Phase08 (post-validation) which detects regressions

7. Computes exit code from `regressions.json` → returns 220

See [Determinism & TestMode](../TESTING-QUALITY/Determinism-and-TestMode.md) for details.

---

### PatchPilot.ps1 (Console Runner)

**Location:** `src/PatchPilot.ps1`

**Synopsis:**

Thin wrapper script that sets the process exit code for CI/RMM integration.

Since `Invoke-PatchPilotRun` is a PowerShell cmdlet (not a native executable), its return value does not automatically set `$LASTEXITCODE`. This wrapper script bridges that gap.

**Usage:**
```powershell
# From PowerShell
.\src\PatchPilot.ps1 -ConfigPath 'config.json' -TestMode
echo "Exit code: $LASTEXITCODE"

# From CI/CD or RMM
pwsh -File .\src\PatchPilot.ps1 -ConfigPath 'config.json' -TenantId 'MSP' -ClientId 'Client'
```

**Parameters:** Same as `Invoke-PatchPilotRun`

**RMM Integration Example:**
```powershell
# In NinjaRMM/ConnectWise/Datto script
& .\PatchPilot.ps1 -ConfigPath $configPath -TenantId $tenantId -ClientId $clientId
if ($LASTEXITCODE -ne 0) {
    Set-RMMAlert -Message "PatchPilot failed: $LASTEXITCODE"
}
exit $LASTEXITCODE
```

---

### Get-PatchPilotExitCodes

Returns deterministic exit code definitions.

**Location:** `src/PatchPilot.Engine/Public/Get-PatchPilotExitCodes.ps1`

**Synopsis:**
Provides machine-readable exit code definitions for automation/RMM integration.

**Syntax:**
```powershell
Get-PatchPilotExitCodes
    [<CommonParameters>]
```

**Returns:** `[PSCustomObject]` with properties:

- `Success` (0)

- `PartialSuccess` (100)

- `RebootRequired` (150)

- `ConcurrencyLock` (170)

- `InstallFailure` (210)

- `ValidationFailure` (220)

- `DiagnosticsFailure` (230)

- `ReportingFailure` (240)

**Example:**
```powershell
PS> Get-PatchPilotExitCodes

Success            : 0
PartialSuccess     : 100
RebootRequired     : 150
ConcurrencyLock    : 170
InstallFailure     : 210
ValidationFailure  : 220
DiagnosticsFailure : 230
ReportingFailure   : 240
```

**RMM Integration:**
```powershell
$codes = Get-PatchPilotExitCodes
$exitCode = Invoke-PatchPilotRun -OutputRoot '...' -ConfigPath '...' ...

if ($exitCode -eq $codes.ValidationFailure) {
    Send-RMMAlert -Severity 'High' -Message 'Regression detected after patching'
}
```

See [Exit Codes](Exit-Codes.md) for detailed explanations.

---

### Get-PatchPilotVersion

Returns engine version.

**Location:** `src/PatchPilot.Engine/Public/Get-PatchPilotVersion.ps1`

**Synopsis:**
Returns the PatchPilot.Engine version.

**Syntax:**
```powershell
Get-PatchPilotVersion
    [<CommonParameters>]
```

**Returns:** `[string]` - Semantic version (e.g., "1.0.0")

**Example:**
```powershell
PS> Get-PatchPilotVersion
1.0.0
```

**Implementation (inferred):**
```powershell
function Get-PatchPilotVersion {
    [CmdletBinding()]
    param()

    # Read from module manifest
    $manifestPath = Join-Path $PSScriptRoot '..\PatchPilot.Engine.psd1'
    $manifest = Import-PowerShellDataFile -Path $manifestPath
    return $manifest.ModuleVersion
}
```

---

### Get-PatchPilotExitCodeFromEvidence

Computes exit code by re-reading persisted evidence.

**Location:** `src/PatchPilot.Engine/Public/Get-PatchPilotExitCodeFromEvidence.ps1`

**Synopsis:**
Evidence-first exit code computation (used in TestMode).

**Syntax:**
```powershell
Get-PatchPilotExitCodeFromEvidence
    -Context <hashtable>
    [<CommonParameters>]
```

**Parameters:**

| Parameter | Type | Mandatory | Description |
|-----------|------|-----------|-------------|
| Context | hashtable | Yes | RunContext hashtable |

**Returns:** `[int]` - Exit code

**Example:**
```powershell
$context = Initialize-RunContext -OutputRoot '...' -ConfigPath '...' `
    -TenantId 'MSP001' -ClientId 'ACME'

# ... run phases ...

$exitCode = Get-PatchPilotExitCodeFromEvidence -Context $context
```

**Implementation (inferred from `Invoke-PatchPilotRun.ps1` lines 249-301):**
```powershell
function Get-PatchPilotExitCodeFromEvidence {
    param([hashtable]$Context)

    # 1) Validation (220)
    $regressionsPath = Join-Path $Context.OutputRoot "Reports\$($Context.RunId)\regressions.json"
    if (Test-Path $regressionsPath) {
        $regressionsReport = Get-Content $regressionsPath -Raw | ConvertFrom-Json
        if ($regressionsReport.TotalRegressions -gt 0) {
            return 220
        }
    }

    # 2) Install (210)
    $installSummaryPath = Join-Path $Context.OutputRoot 'Logs\install-summary.jsonl'
    if (Test-Path $installSummaryPath) {
        $installRecords = Get-Content $installSummaryPath | ForEach-Object { $_ | ConvertFrom-Json }
        if ($installRecords | Where-Object { -not $_.installed }) {
            return 210
        }
    }

    # 3) Reboot (150)
    # ... (check rebootRequired + deferralDays)

    # 4) Reporting (240)
    # ... (check final-report.json)

    # 5) Success
    return 0
}
```

---

## Private Functions

These functions are internal helpers (not exported). Listed for reference.

### Initialize-RunContext

Initializes RunContext hashtable.

**Location:** `src/PatchPilot.Engine/Private/Initialize-RunContext.ps1`

**Returns:** `[hashtable]` with keys:

- `TenantId`, `ClientId`, `SiteId`, `DeviceId`

- `RunId` (GUID)

- `OutputRoot`

- `ConfigPath`

- `ToolVersion`

- `StartTime` (UTC)

- `Checkpoint` (hashtable)

- `ExitCode` (int, initialized to 0)

### New-EventRecord

Emits structured event to `Logs\Events.jsonl` with hash chaining.

**Location:** `src/PatchPilot.Engine/Private/New-EventRecord.ps1`

**Parameters:**

- `Context` (hashtable)

- `Event` (string) - Event name (e.g., "PhaseStart")

- `Level` (string) - "Info", "Warning", or "Error"

- `Data` (hashtable) - Event payload

### Save-Checkpoint

Persists checkpoint to `State\state.json`.

**Location:** `src/PatchPilot.Engine/Private/Save-Checkpoint.ps1`

**Parameters:**

- `Context` (hashtable)

- `Phase` (string) - Phase ID (e.g., "Phase02")

- `Step` (string) - Step name (e.g., "CaptureServices")

### Test-StepCompleted

Checks if a step was already completed.

**Location:** `src/PatchPilot.Engine/Private/Test-StepCompleted.ps1`

**Parameters:**

- `Context` (hashtable)

- `Phase` (string)

- `Step` (string)

**Returns:** `[bool]`

### Get-FileSha256

Computes SHA-256 hash of a file.

**Location:** `src/PatchPilot.Engine/Private/Get-FileSha256.ps1`

**Parameters:**

- `Path` (string)

**Returns:** `[string]` - Hex SHA-256 hash

### Add-Artifact

Adds an artifact entry (for Phase10 indexing).

**Location:** `src/PatchPilot.Engine/Private/Add-Artifact.ps1`

**Parameters:**

- `Context` (hashtable)

- `Path` (string)

- `Category` (string)

### New-ArtifactIndex

Scans artifacts and builds `artifact-index.json`.

**Location:** `src/PatchPilot.Engine/Private/New-ArtifactIndex.ps1`

**Parameters:**

- `Context` (hashtable)

### Write-Manifest

Computes Merkle root and writes `manifest.json`.

**Location:** `src/PatchPilot.Engine/Private/Write-Manifest.ps1`

**Parameters:**

- `Context` (hashtable)

### Test-PhaseAttempted

Checks if a phase was attempted (for exit code logic).

**Location:** `src/PatchPilot.Engine/Private/Test-PhaseAttempted.ps1`

**Parameters:**

- `Context` (hashtable)

- `PhaseId` (string)

**Returns:** `[bool]`

### Phase Functions

- `Invoke-Phase02` - Baseline Snapshot
- `Invoke-Phase03` - Update Classification Fetch
- `Invoke-Phase04` - Pre-Validation
- `Invoke-Phase05` - Patch Install
- `Invoke-Phase06` - Reboot Orchestration
- `Invoke-Phase07` - Post-Snapshot
- `Invoke-Phase08` - Post-Validation
- `Invoke-Phase09` - Diagnostics/LightDiag
- `Invoke-Phase11` - Reporting

**All located in:** `src/PatchPilot.Engine/Private/`

**Common Parameters:**
- `Context` (hashtable) - RunContext

See [Phases](../ARCHITECTURE/Phases.md) for detailed phase descriptions.

---

## Usage Patterns

### Basic Patch Cycle

```powershell
Import-Module .\src\PatchPilot.Engine\PatchPilot.Engine.psd1

$exitCode = Invoke-PatchPilotRun `
    -OutputRoot 'C:\PatchPilot\Output' `
    -ConfigPath 'C:\PatchPilot\Config\ClientProfile.json' `
    -TenantId 'MSP001' `
    -ClientId 'ACME'

# Check exit code
if ($exitCode -eq 0) {
    Write-Output "Success"
    exit 0
} else {
    Write-Output "Exit code: $exitCode"
    exit $exitCode
}
```

### RMM Integration

```powershell
# Scheduled task or RMM agent script
$exitCodes = Get-PatchPilotExitCodes
$result = Invoke-PatchPilotRun -OutputRoot '...' -ConfigPath '...' `
    -TenantId $env:TENANT_ID -ClientId $env:CLIENT_ID

# Send telemetry to RMM
Send-RMMMetric -Name 'PatchPilot.ExitCode' -Value $result
Send-RMMMetric -Name 'PatchPilot.Success' -Value ($result -eq $exitCodes.Success)

# Upload final report
$reportPath = Get-ChildItem -Path 'C:\PatchPilot\Output\Reports' -Recurse -Filter 'final-report.json' |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
Send-RMMFile -Path $reportPath.FullName -Category 'PatchReports'

exit $result
```

### TestMode Validation

```powershell
# Run in TestMode to verify regression detection
$exitCode = Invoke-PatchPilotRun `
    -OutputRoot 'C:\PatchPilot\Test' `
    -ConfigPath 'C:\PatchPilot\Config\ClientProfile.json' `
    -TenantId 'TEST' `
    -ClientId 'VALIDATION' `
    -TestMode

# Should return 220 (ValidationFailure) if regression detection works
if ($exitCode -eq 220) {
    Write-Output "TestMode regression detection: PASS"
} else {
    Write-Error "TestMode regression detection: FAIL (expected 220, got $exitCode)"
}
```

---

## References

- [Exit Codes](Exit-Codes.md)
- [Artifacts & Schemas](Artifacts-and-Schemas.md)
- [User Guide](../OPERATIONS/User-Guide.md)
- [RMM Integration](../OPERATIONS/RMM-Integration.md)
