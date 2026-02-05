# ITSM Change Control Integration

## Overview

Integrate PatchPilot with ITSM platforms for change management.

## Change Request Template

**Change Title:** Windows Patch Deployment - [Client] - [Date]

**Description:**
- Deploy patches per UpdatePolicy.json
- Affected systems: [Device list]
- Maintenance window: [Start] to [End]

**Risk Assessment:**
- Pre-validation: Application health checks
- Rollback plan: Baseline snapshot captured
- Evidence: Merkle root in manifest.json

**Implementation:**

```powershell
Invoke-PatchPilotRun -OutputRoot "C:\PatchPilot\Output" -PolicyProfileId "Production"
```

**Verification:**
- Exit code: 0 (success) or 150 (reboot required)
- Final report: final-report.html
- Standards mapping: NIST/CIS compliance

## ServiceNow Integration

```powershell
# Create change request
$change = @{
    short_description = "PatchPilot Deployment"
    category = "Software"
    impact = 2
    urgency = 2
    start_date = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
}

$headers = @{
    Authorization = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$user:$pass"))
}

Invoke-RestMethod -Uri "https://instance.service-now.com/api/now/table/change_request" -Method Post -Headers $headers -Body ($change | ConvertTo-Json)

# Run PatchPilot
$exitCode = Invoke-PatchPilotRun -OutputRoot "C:\PatchPilot\Output"

# Update change request with results
# Attach final-report.html
```

## Evidence for Auditors

```powershell
$manifest = Get-Content "$outputRoot\manifest.json" | ConvertFrom-Json

$auditPackage = @{
    ChangeNumber = "CHG0012345"
    RunId = $manifest.runId
    MerkleRoot = $manifest.merkleRoot
    ExitCode = $exitCode
    Timestamp = $manifest.startTime
}

$auditPackage | ConvertTo-Json | Out-File "$outputRoot\audit-package.json"
```

## See Also

- [RMM Integration](./RMM-Integration.md)
- [Audit Playbook](../SECURITY-COMPLIANCE/Audit-Playbook.md)
- [Change Record Template](../APPENDICES/Change-Record-Template.md)
