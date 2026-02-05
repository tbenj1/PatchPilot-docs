# PatchPilot Developer Guide

## Overview

This guide is for developers contributing to PatchPilot or building custom integrations. It covers architecture, coding standards, testing, and contribution workflows.

## Repository Structure

```
PatchPilot/
├── src/
│   ├── PatchPilot.ps1                    # Console runner / RMM wrapper
│   ├── PatchPilot.Engine/                # Core module
│   │   ├── PatchPilot.Engine.psd1        # Module manifest
│   │   ├── PatchPilot.Engine.psm1        # Module loader
│   │   ├── Public/                       # Exported functions
│   │   │   ├── Invoke-PatchPilotRun.ps1
│   │   │   ├── Get-PatchPilotExitCodes.ps1
│   │   │   ├── Get-PatchPilotExitCodeFromEvidence.ps1
│   │   │   └── Get-PatchPilotVersion.ps1
│   │   └── Private/                      # Internal implementation
│   │       ├── Invoke-Phase01.ps1        # Initialization
│   │       ├── Invoke-Phase02.ps1        # Baseline Snapshot
│   │       ├── Invoke-Phase03.ps1        # Update Catalog
│   │       ├── Invoke-Phase04.ps1        # Pre-Validation
│   │       ├── Invoke-Phase05.ps1        # Patch Install
│   │       ├── Invoke-Phase06.ps1        # Reboot Orchestration
│   │       ├── Invoke-Phase07.ps1        # Post-Snapshot
│   │       ├── Invoke-Phase08.ps1        # Post-Validation
│   │       ├── Invoke-Phase09.ps1        # Diagnostics (LightDiag)
│   │       ├── Invoke-Phase10.ps1        # Evidence Indexing
│   │       ├── Invoke-Phase11.ps1        # Reporting
│   │       ├── Initialize-RunContext.ps1
│   │       ├── New-EventRecord.ps1
│   │       ├── Save-Checkpoint.ps1
│   │       ├── Test-PhaseAttempted.ps1
│   │       ├── Test-StepCompleted.ps1
│   │       ├── New-ArtifactIndex.ps1
│   │       ├── Write-Manifest.ps1
│   │       ├── Add-Artifact.ps1
│   │       └── Get-FileSha256.ps1
├── data/
│   └── schemas/                          # JSON schemas
│       ├── events.schema.json
│       ├── manifest.schema.json
│       ├── config.schema.json
│       └── ...
├── examples/
│   ├── configs/                          # Sample configurations
│   │   └── lab/
│   │       ├── NoOp.json
│   │       └── Comprehensive.json
│   └── rmm-integration/                  # RMM integration kits
│       ├── README.md
│       └── n-able/
│           ├── Deploy-PatchPilot.ps1
│           ├── Run-PatchPilot.ps1
│           ├── Collect-Evidence.ps1
│           ├── Send-PatchPilotNotification.ps1
│           └── ...
├── tests/                                # Pester tests
│   ├── StageC.Tests.ps1
│   ├── StageD.Tests.ps1
│   ├── StageE.Tests.ps1
│   ├── StageF.Tests.ps1
│   ├── StageG.Tests.ps1
│   ├── StageH.Tests.ps1
│   ├── StageI.Tests.ps1
│   └── ...
├── docs/                                 # MkDocs documentation
│   ├── README.md
│   ├── ARCHITECTURE/
│   ├── API/
│   ├── OPERATIONS/
│   ├── GUIDES/
│   └── BUILD/
│       └── mkdocs.yml
├── tools/                                # Development utilities
└── README.md                             # Project overview
```

## Architecture Principles

### 1. Evidence-First Design

**Core Tenet:** All decisions must be derivable from persisted artifacts, never from ephemeral in-memory state.

**Implementation:**
```powershell
# ❌ BAD: Decision based on in-memory variable
$patchesInstalled = $installedList.Count
if ($patchesInstalled -gt 0) {
    # Generate report
}

# ✅ GOOD: Decision based on persisted evidence
$installSummaryPath = Join-Path $Context.OutputRoot 'Logs\install-summary.jsonl'
if (Test-Path $installSummaryPath) {
    $recs = Get-Content $installSummaryPath | ForEach-Object { $_ | ConvertFrom-Json }
    $patchesInstalled = ($recs | Where-Object { $_.installed }).Count
    # Generate report based on artifact
}
```

### 2. No Global State

**Core Tenet:** Everything must flow via the `RunContext` hashtable or explicit parameters.

**Implementation:**
```powershell
# ❌ BAD: Global variable
$global`:CurrentRunId = ([guid]::NewGuid()).ToString()

# ✅ GOOD: Passed via context
$Context.RunId = ([guid]::NewGuid()).ToString()
```

### 3. Non-Interactive by Design

**Core Tenet:** No prompts, no UI dependencies, deterministic outputs.

**Implementation:**
```powershell
# ❌ BAD: Interactive prompt
$confirm = Read`-Host "Continue with patching? (y/n)"

# ✅ GOOD: Configuration-driven decision
$autoPatch = $config.updatePolicy.automaticInstall
if ($autoPatch) {
    # Proceed
}
```

### 4. Deterministic Exit Codes

**Core Tenet:** Exit codes must be computable from evidence alone (evidence-first).

**Implementation:**
```powershell
# Exit code calculation in Get-PatchPilotExitCodeFromEvidence.ps1
# Reads persisted artifacts (regressions.json, install-summary.jsonl, etc.)
# Returns deterministic code based ONLY on file contents
```

## Coding Standards

### PowerShell Version

**Requirement:** PowerShell 7.0+

**Enforcement:**
```powershell
#Requires -Version 7.0
```

### Approved Verbs

**Requirement:** All exported functions must use PowerShell approved verbs.

**Verification:**
```powershell
Get-Verb  # Check if verb is approved
```

**Common Approved Verbs:**
- `Get-` - Retrieve data
- `Set-` - Modify data
- `New-` - Create new resource
- `Remove-` - Delete resource
- `Invoke-` - Execute action
- `Test-` - Validate condition
- `Write-` - Output data

### No Write`-Host

**Requirement:** Use structured logging (`New-EventRecord`) instead of `Write`-Host`.

**Rationale:** `Write`-Host` bypasses standard output streams and can't be captured by RMM systems.

```powershell
# ❌ BAD
Write`-Host "Phase01 started" -ForegroundColor Green

# ✅ GOOD
New-EventRecord -Context $Context -Event 'PhaseStart' -Level 'Info' -Data @{
    phaseId = 'Phase01'
    name = 'Initialization'
}
```

### UTF-8 Encoding (No BOM)

**Requirement:** All JSON/JSONL output must use UTF-8 without BOM.

```powershell
# ✅ GOOD
$data | ConvertTo-Json -Depth 10 | Set-Content -Path $outputPath -Encoding utf8NoBOM
```

### Consistent Casing

**JSON Keys:** camelCase
```json
{
  "runId": "abc-123",
  "generatedAtUtc": "2026-01-30T12:00:00Z",
  "schemaVersion": "1.0"
}
```

**PowerShell Identifiers:** PascalCase
```powershell
$RunContext = @{}
$OutputRoot = "C:\PatchPilot\Output"
```

### Schema Versioning

**Requirement:** All JSON artifacts must include `schemaVersion` field.

```json
{
  "schemaVersion": "1.0",
  "runId": "...",
  ...
}
```

## RunContext Contract

The `RunContext` hashtable is the single source of truth passed through all phases.

### Required Fields

```powershell
$Context = @{
    # Identity
    RunId = [string]              # GUID
    TenantId = [string]
    ClientId = [string]
    SiteId = [string]
    DeviceId = [string]

    # Paths
    OutputRoot = [string]         # C:\PatchPilot\Output\Runs\<RunId>
    ConfigPath = [string]
    DeviceStateRoot = [string]    # Optional: cross-run state

    # Config
    Config = [hashtable]          # Parsed JSON config

    # Runtime Flags
    TestMode = [bool]             # Offline/simulation mode
    Resumed = [bool]              # Post-reboot resume

    # Timestamps
    StartTimeUtc = [string]       # ISO 8601

    # Schema
    schemaVersion = [string]      # "1.0"

    # Paths (computed)
    Paths = @{
        Logs = [string]
        Artifacts = [string]
        Reports = [string]
        Telemetry = [string]
        State = [string]
    }

    # Exit Code (set by phases)
    ExitCode = [int]              # Set on critical failures
}
```

### Context Initialization

```powershell
# In Initialize-RunContext.ps1
$Context = @{
    RunId = $RunId
    TenantId = $TenantId
    # ... populate all required fields
}

# Compute derived paths
$Context.Paths = @{
    Logs = Join-Path $Context.OutputRoot 'Logs'
    Artifacts = Join-Path $Context.OutputRoot 'Artifacts'
    Reports = Join-Path $Context.OutputRoot 'Reports'
    Telemetry = Join-Path $Context.OutputRoot 'Telemetry'
    State = Join-Path $Context.OutputRoot 'State'
}
```

## Phase Development

### Phase Template

```powershell
#Requires -Version 7.0

<#
.SYNOPSIS
    Phase## - [Phase Name]
.DESCRIPTION
    [Detailed description of what this phase does]
#>

function Invoke-Phase## {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Context
    )

    # Emit PhaseStart event
    New-EventRecord -Context $Context -Event 'PhaseStart' -Level 'Info' -Data @{
        phaseId = 'Phase##'
        name = '[Phase Name]'
    }

    # Check if already completed (idempotency)
    if (Test-StepCompleted -Context $Context -Phase 'Phase##' -Step 'Complete') {
        New-EventRecord -Context $Context -Event 'PhaseEnd' -Level 'Info' -Data @{
            phaseId = 'Phase##'
            success = $true
            skipped = $true
        }
        return
    }

    try {
        # Phase logic here

        # Save checkpoint on success
        Save-Checkpoint -Context $Context -Phase 'Phase##' -Step 'Complete'

        # Emit PhaseEnd event
        New-EventRecord -Context $Context -Event 'PhaseEnd' -Level 'Info' -Data @{
            phaseId = 'Phase##'
            success = $true
        }
    }
    catch {
        $msg = $_.Exception.Message
        New-EventRecord -Context $Context -Event 'Phase##Error' -Level 'Error' -Data @{
            phaseId = 'Phase##'
            message = $msg
        }

        # Set exit code if critical
        # $Context.ExitCode = 240

        throw
    }
}
```

### Event Logging

**Standard Events:**
- `PhaseStart` - Beginning of phase
- `PhaseEnd` - Successful completion
- `[Phase]Error` - Phase-specific error
- `[Phase]Warning` - Non-fatal issue

**Example:**
```powershell
New-EventRecord -Context $Context -Event 'PatchInstallStart' -Level 'Info' -Data @{
    updateCount = $updates.Count
    classification = $updates[0].Classification
}

New-EventRecord -Context $Context -Event 'PatchInstallComplete' -Level 'Info' -Data @{
    installed = $installedCount
    failed = $failedCount
    rebootRequired = [bool]$needsReboot
}
```

## Testing

### Test Structure

Tests are organized by stage (progressive validation):

- **StageC** - Baseline artifact validation
- **StageD** - Config parsing and policy validation
- **StageE** - Update catalog validation
- **StageF** - Full TestMode execution
- **StageG** - Checkpoint and resume logic
- **StageH** - Evidence indexing and manifest validation
- **StageI** - Regression detection and exit code logic

### Writing Tests

```powershell
# tests/MyFeature.Tests.ps1

Describe "MyFeature" {
    BeforeAll {
        # Setup test environment
        $testOutputRoot = Join-Path $env:TEMP "PatchPilot-Test-$(New-Guid)"
        New-Item -ItemType Directory -Path $testOutputRoot -Force | Out-Null

        # Import module
        Import-Module "$PSScriptRoot/../src/PatchPilot.Engine/PatchPilot.Engine.psd1" -Force
    }

    It "Should produce expected artifact" {
        # Arrange
        $Context = @{
            RunId = ([guid]::NewGuid()).ToString()
            OutputRoot = $testOutputRoot
            # ... minimal context
        }

        # Act
        Invoke-MyPhase -Context $Context

        # Assert
        $artifactPath = Join-Path $testOutputRoot 'expected-artifact.json'
        $artifactPath | Should -Exist

        $artifact = Get-Content $artifactPath -Raw | ConvertFrom-Json
        $artifact.schemaVersion | Should -Be '1.0'
    }

    AfterAll {
        # Cleanup
        Remove-Item -Path $testOutputRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
```

### Running Tests

```powershell
# Run all tests
Invoke-Pester -Path ./tests/ -Output Detailed

# Run specific test file
Invoke-Pester -Path ./tests/StageF.Tests.ps1 -Output Detailed

# Run with coverage
Invoke-Pester -Path ./tests/ -CodeCoverage ./src/PatchPilot.Engine/**/*.ps1 -Output Detailed
```

## Contributing Workflow

### 1. Fork and Clone

```bash
git clone https://github.com/YOUR-USERNAME/PatchPilot.git
cd PatchPilot
```

### 2. Create Feature Branch

```bash
git checkout -b feature/my-new-feature
```

### 3. Make Changes

- Follow coding standards
- Add/update tests
- Update documentation

### 4. Test Locally

```powershell
# Run tests
Invoke-Pester -Path ./tests/ -Output Detailed

# Test in TestMode
pwsh -NoProfile -File ./src/PatchPilot.ps1 -ConfigPath ./examples/configs/lab/NoOp.json -TestMode

# Verify exit code
echo $LASTEXITCODE  # Should be 0
```

### 5. Commit and Push

```bash
git add .
git commit -m "Add: Brief description of changes"
git push origin feature/my-new-feature
```

### 6. Create Pull Request

- Title: Brief summary (e.g., "Add: Email notification system")
- Description:
  - **What:** Description of changes
  - **Why:** Rationale for changes
  - **Testing:** How you tested (include evidence/screenshots)
  - **Breaking Changes:** Any BC breaks

## Debugging

### Enable Verbose Logging

```powershell
$VerbosePreference = 'Continue'
Invoke-PatchPilotRun -OutputRoot $outputRoot -ConfigPath $config -Verbose
```

### Inspect Events Log

```powershell
$eventsPath = Join-Path $outputRoot 'Runs\<RunId>\Logs\Events.jsonl'
Get-Content $eventsPath | ForEach-Object {
    $_ | ConvertFrom-Json | Format-List
}
```

### Breakpoint Debugging

```powershell
# In VS Code, set breakpoint in phase file
# Press F5 to debug

# Or use PSScriptAnalyzer
Invoke-ScriptAnalyzer -Path ./src/PatchPilot.Engine/Private/Invoke-Phase09.ps1
```

## Building Documentation

### Install Dependencies

```bash
pip install mkdocs mkdocs-material pymdown-extensions
```

### Build Locally

```bash
cd docs/BUILD
mkdocs serve
# Navigate to http://127.0.0.1:8000
```

### Build Static Site

```bash
cd docs/BUILD
mkdocs build
# Output in ../../_site/
```

## Release Process

### Version Numbering

Follow [Semantic Versioning](https://semver.org/):
- **MAJOR.MINOR.PATCH**
- Example: `1.2.3`

### Creating a Release

1. **Update Version**
   ```powershell
   # In src/PatchPilot.Engine/PatchPilot.Engine.psd1
   ModuleVersion = '1.2.3'
   ```

2. **Update CHANGELOG**
   ```markdown
   ## [1.2.3] - 2026-01-30
   ### Added
   - Email notification system
   - N-able RMM integration kit
   ### Fixed
   - Exit code 230 propagation
   ```

3. **Tag Release**
   ```bash
   git tag -a v1.2.3 -m "Release v1.2.3"
   git push origin v1.2.3
   ```

4. **Create GitHub Release**
   - Navigate to Releases on GitHub
   - Create new release from tag
   - Attach ZIP of module

## See Also

- [Architecture Overview](ARCHITECTURE/Architecture.md)
- [API Reference](API/PowerShell-Module-Reference.md)
- [Testing Strategy](TESTING-QUALITY/Test-Strategy.md)
- [RMM Integration Guide](OPERATIONS/RMM-Integration.md)
