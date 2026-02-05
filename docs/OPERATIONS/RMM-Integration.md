# RMM Integration Guide

## Overview

PatchPilot is designed for seamless integration with Remote Monitoring and Management (RMM) platforms commonly used by Managed Service Providers (MSPs). This guide covers integration architecture, best practices, and platform-specific implementations.

## Integration Architecture

### Core Principles

1. **Non-Interactive Execution** - All operations run headless without user prompts
2. **Deterministic Exit Codes** - Machine-readable outcomes for automation (0, 150, 170, 210, 220, 230, 240)
3. **Evidence-First** - All decisions derive from persisted artifacts
4. **RMM-Agnostic Core** - PatchPilot.Engine has no RMM dependencies
5. **Thin Wrapper Pattern** - RMM-specific logic isolated in integration scripts

### Three-Phase Integration Pattern

All RMM integrations follow a consistent pattern:

```
┌─────────────────────────────────────────────────────────┐
│                    RMM Platform                         │
│              (N-able, Datto, Kaseya, etc.)             │
└────────────┬──────────────┬──────────────┬─────────────┘
             │              │              │
   ┌─────────▼─────────┐   │   ┌─────────▼──────────┐
   │  Phase 1: Deploy  │   │   │  Phase 3: Collect  │
   │                   │   │   │                    │
   │ - Install PS7     │   │   │ - Package evidence │
   │ - Deploy module   │   │   │ - Upload to RMM    │
   │ - Validate setup  │   │   │ - Create tickets   │
   └───────────────────┘   │   │ - Apply retention  │
                           │   └────────────────────┘
                 ┌─────────▼──────────┐
                 │  Phase 2: Execute  │
                 │                    │
                 │ - Download config  │
                 │ - Check maintenance│
                 │ - Invoke PatchPilot│
                 │ - Propagate codes  │
                 │ - Update inventory │
                 └────────────────────┘
```

## Available Integrations

### Production-Ready

#### N-able RMM (N-central, RMM, MSP Manager)

**Location:** `examples/rmm-integration/n-able/`

**Components:**
- `Deploy-PatchPilot.ps1` - One-time deployment
- `Run-PatchPilot.ps1` - Weekly execution wrapper
- `Collect-Evidence.ps1` - Artifact collection
- `Send-PatchPilotNotification.ps1` - Email notifications
- `New-PatchPilotEmailConfig.ps1` - Email configuration wizard

**Features:**
- Automated PowerShell 7 installation
- Multi-source module deployment (GitHub, FileShare, N-able Repo)
- Maintenance window detection
- Retry logic for concurrency locks
- Custom property integration
- Evidence upload to N-able Files
- Automatic ticket creation on failures
- Rich HTML email notifications (Office 365, Gmail, SendGrid)

**Quick Start:**
```powershell
# 1. Deploy (one-time)
.\Deploy-PatchPilot.ps1

# 2. Execute (weekly automation)
.\Run-PatchPilot.ps1 `
  -ConfigUrl "https://files.n-able.com/PatchPilot/Client.json" `
  -TenantId "MSP001" `
  -ClientId "ACME"

# 3. Configure email notifications
.\New-PatchPilotEmailConfig.ps1
.\Send-PatchPilotNotification.ps1 -TestConnection
```

**Documentation:**
- [N-able Integration README](../../examples/rmm-integration/n-able/README.md)
- [Deployment Guide](../../examples/rmm-integration/n-able/DEPLOYMENT-GUIDE.md)
- [Email Notifications](../../examples/rmm-integration/n-able/EMAIL-NOTIFICATIONS.md)
- [Quick Reference Card](../../examples/rmm-integration/n-able/QUICK-REFERENCE.md)

### Coming Soon

- **Datto RMM** - Planned Q2 2026
- **Kaseya VSA** - Planned Q2 2026
- **ConnectWise Automate** - Planned Q3 2026
- **NinjaOne** - Planned Q3 2026
- **Atera** - Community contributions welcome

## Exit Code Integration

All RMM platforms must propagate PatchPilot exit codes to monitoring/alerting systems:

| Exit Code | Meaning | RMM Alert Level | Typical Action |
|-----------|---------|-----------------|----------------|
| **0** | Success | Normal | Log success, no alerts |
| **150** | Reboot Required | Warning | Trigger reboot automation |
| **170** | Concurrency Lock | Warning | Retry in 30 minutes |
| **210** | Install Failure | Critical | Escalate to technician |
| **220** | Validation Failure | Critical | Review regressions report |
| **230** | Diagnostics Failure | High | Review diagnostics artifacts |
| **240** | Reporting/Critical | Critical | Emergency escalation |

### RMM-Specific Exit Code Handling

**N-able:**
```powershell
# In Run-PatchPilot.ps1
$finalExitCode = Invoke-PatchPilotRun -OutputRoot $outputRoot -ConfigPath $configPath ...
exit $finalExitCode  # Propagates to N-able dashboard
```

**Datto RMM:**
```powershell
# Use Datto's exit code system
$exitCode = Invoke-PatchPilotRun ...
Set-DattoVariable -Name "PatchPilot_ExitCode" -Value $exitCode
exit $exitCode
```

**Generic PowerShell:**
```powershell
# Standard pattern for any RMM
pwsh -NoProfile -File "Run-PatchPilot.ps1" -ConfigPath $config
$exitCode = $LASTEXITCODE
if ($exitCode -ne 0) {
    # Trigger RMM alert based on code
}
```

## Validated invocation patterns

For quoting-safe `pwsh -Command` patterns that consistently propagate exit codes (and avoid PowerShell parameter-binding pitfalls), see:

- [Local Execution & Validation](Local-Execution-and-Validation.md)

## Configuration Management

See full RMM integration guide in `examples/rmm-integration/` for detailed configuration strategies, security best practices, and complete implementation examples.

## Email Notifications

PatchPilot includes a rich email notification system supporting:

- **Office 365 / Outlook.com**
- **Gmail** (App Passwords)
- **SendGrid**
- **Custom SMTP**

**Quick Setup:**
```powershell
.\New-PatchPilotEmailConfig.ps1  # Interactive wizard
.\Send-PatchPilotNotification.ps1 -TestConnection  # Test
```

**See:** [Email Notifications Guide](../../examples/rmm-integration/n-able/EMAIL-NOTIFICATIONS.md)

## See Also

- [N-able Integration Kit](../../examples/rmm-integration/n-able/README.md)
- [Exit Codes Reference](../API/Exit-Codes.md)
- [User Guide](User-Guide.md)
- [Troubleshooting](Troubleshooting.md)
