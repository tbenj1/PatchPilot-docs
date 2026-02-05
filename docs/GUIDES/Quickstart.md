# Quickstart

Get started with PatchPilot in 5 minutes.

## Prerequisites

- **PowerShell 7.0+** (required)
- **Windows** (target system)
- **Administrator privileges** (for patching operations)

## Installation

```powershell
# Clone or download the repository
git clone https://github.com/msp/patchpilot.git

# Import the module
Import-Module .\src\PatchPilot.Engine\PatchPilot.Engine.psd1

# Verify installation
Get-PatchPilotVersion
# Output: 1.0.0
```

### Note on execution policy (development)

If you're running from source and the files are not code-signed, some hosts will block module import. For **local testing only**, use process-scope bypass:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
Get-ChildItem -Recurse -File | Unblock-File -ErrorAction SilentlyContinue
```

## Quick Test (Offline Mode)

Run PatchPilot in offline/test mode using the included lab config:

```powershell
# From repo root
$exitCode = Invoke-PatchPilotRun `
    -ConfigPath 'examples\configs\lab\NoOp.json' `
    -TestMode

# Check exit code (220 = regression detected, which is expected in TestMode)
Write-Output "Exit code: $exitCode"
```

**Wrapper default output location:** If you run `./src/PatchPilot.ps1` without `-OutputRoot` and `config.outputRoot` is not set, output defaults to `$env:LOCALAPPDATA\PatchPilot\Runs\<RunId>\` (RunId is a GUID).

## Validated full local real run (NON-TestMode)

This runs PatchPilot end-to-end and asserts that the minimum artifacts exist and that there are no `Error`/`Fatal` events in `Events.jsonl`.

```powershell
$repo = "A:\Career Advancement\Professional Projects\PatchPilot\PatchPilot\PatchPilot"
Set-Location $repo

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
Get-ChildItem -Path $repo -Recurse -File | Unblock-File -ErrorAction SilentlyContinue

Import-Module .\src\PatchPilot.Engine\PatchPilot.Engine.psd1 -Force

$code = Invoke-PatchPilotRun `
  -OutputRoot "$env:LOCALAPPDATA\PatchPilot" `
  -ConfigPath ".\examples\configs\lab\NoOp.json" `
  -TenantId "MSP001" -ClientId "ACME" -SiteId "HQ" -DeviceId $env:COMPUTERNAME

$latest = Get-ChildItem "$env:LOCALAPPDATA\PatchPilot\Runs" -Directory |
  Sort-Object LastWriteTime -Descending | Select-Object -First 1
$runId = Split-Path -Leaf $latest.FullName

$mustExist = @(
  (Join-Path $latest.FullName "run.json"),
  (Join-Path $latest.FullName "Logs\Events.jsonl"),
  (Join-Path $latest.FullName "Artifacts\UpdateCatalog\$runId\catalog.json"),
  (Join-Path $latest.FullName "Reports\final-report.json"),
  (Join-Path $latest.FullName "Reports\final-report.html")
)
$missing = $mustExist | Where-Object { -not (Test-Path $_) }

$events = Get-Content (Join-Path $latest.FullName "Logs\Events.jsonl") |
  ForEach-Object { try { $_ | ConvertFrom-Json } catch { $null } } |
  Where-Object { $_ }
$bad = $events | Where-Object { $_.Level -in @('Error','Fatal') }

if ($code -ne 0) { throw "FAIL: ExitCode=$code (RunId=$runId)" }
if ($missing)    { throw ("FAIL: Missing expected artifacts: " + ($missing -join '; ')) }
if ($bad)        { throw "FAIL: Run contains Error/Fatal events (RunId=$runId)." }

"PASS: Full real run succeeded (RunId=$runId ExitCode=$code)"
```

See also: [Local Execution & Validation](../OPERATIONS/Local-Execution-and-Validation.md)

## Two Modes of Operation

### 1. Online Mode (Production)

For MSP environments with multi-tenant identification:

```powershell
$exitCode = Invoke-PatchPilotRun `
    -OutputRoot 'C:\PatchPilot\Output' `
    -ConfigPath 'C:\Config\ClientProfile.json' `
    -TenantId 'MSP001' `
    -ClientId 'ACME'

# Handle exit code
switch ($exitCode) {
    0   { Write-Output "Success" }
    150 { Write-Output "Reboot required" }
    210 { Write-Output "Install failure" }
    220 { Write-Output "Validation failure" }
    240 { Write-Output "Critical failure" }
}
```

### 2. Offline Mode (Lab/Testing)

For development, testing, or environments without Graph/AAD:

```powershell
# TenantId and ClientId are optional in offline mode
$exitCode = Invoke-PatchPilotRun `
    -OutputRoot 'C:\Test\Output' `
    -ConfigPath 'examples\configs\lab\NoOp.json' `
    -TestMode
```

## Configuration Files

PatchPilot uses JSON configuration files. Relative paths in configs are resolved relative to the config file's directory.

**Example config structure:**
```
C:\Config\
  ClientProfile.json          # Main config
  policies\
    AppValidationPolicy.json  # Referenced as "policies\AppValidationPolicy.json"
    UpdatePolicy.json
```

**ClientProfile.json:**
```json
{
  "profileId": "ACME-PROD",
  "AppValidationPolicyPath": "policies\\AppValidationPolicy.json"
}
```

## Output Structure

Each run creates a run folder under `OutputRoot\Runs\<RunId>\`, where `RunId` is a GUID:

```
OutputRoot\
  Runs\
    <RunId>\                 # Run folder (RunId GUID)
      Logs\
        Events.jsonl          # Hash-chained event log
        install-summary.jsonl # Update install results (one line per update)
      Artifacts\
      Reports\
        regressions.json      # Regression analysis
        final-report.json     # Summary report
        final-report.html     # Human-readable report
      Telemetry\
      State\
        state.json            # Checkpoint state
      run.json                # Run metadata + exit code
  State\
    Tenants\<TenantId>\Clients\<ClientId>\Sites\<SiteId>\Devices\<DeviceId>\
      lock.json               # Per-device concurrency lock
      reboot-required.json    # Reboot cookie (created only when needed)
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 150 | Reboot Required (deferred) |
| 170 | Concurrency Lock |
| 210 | Install Failure |
| 220 | Validation Failure (Regression) |
| 240 | Critical Failure |

## CI/RMM Integration

Use the console runner script for proper exit code handling:

```powershell
# Sets $LASTEXITCODE for CI/RMM tools
.\src\PatchPilot.ps1 -ConfigPath 'config.json' -TenantId 'MSP' -ClientId 'Client'
echo "Exit code: $LASTEXITCODE"
```

## Next Steps

- [PowerShell Module Reference](../API/PowerShell-Module-Reference.md) - Full API documentation
- [Exit Codes](../API/Exit-Codes.md) - Detailed exit code explanations
- [Policy Authoring](Policy-Authoring.md) - Create custom policies
- [User Guide](../OPERATIONS/User-Guide.md) - Comprehensive usage guide
- [Troubleshooting](../OPERATIONS/Troubleshooting.md) - Common issues and solutions
