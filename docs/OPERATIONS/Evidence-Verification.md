# Evidence Verification Guide

## Overview

PatchPilot implements cryptographic evidence integrity:
- SHA-256 artifact hashing
- Hash chaining for events  
- Merkle root over artifacts

Referenced schemas: `data/schemas/events.schema.json`, `artifact-index.schema.json`, `manifest.schema.json`

## Hash Chain Verification

```powershell
$events = Get-Content "C:\PatchPilot\Output\Logs\Events.jsonl" | ConvertFrom-Json
$sha256 = [System.Security.Cryptography.SHA256]::Create()

for ($i = 1; $i -lt $events.Count; $i++) {
    $prevJson = $events[$i - 1] | ConvertTo-Json -Compress
    $prevHash = [BitConverter]::ToString($sha256.ComputeHash([Text.Encoding]::UTF8.GetBytes($prevJson))).Replace("-", "").ToLower()
    
    if ($events[$i].prevHash -ne $prevHash) {
        throw "Chain broken at event $i"
    }
}
```

## Artifact Index Verification

```powershell
$index = Get-Content "C:\PatchPilot\Output\artifact-index.json" | ConvertFrom-Json

foreach ($artifact in $index) {
    $fullPath = Join-Path "C:\PatchPilot\Output" $artifact.path
    $actualHash = (Get-FileHash -Path $fullPath -Algorithm SHA256).Hash.ToLower()
    
    if ($actualHash -ne $artifact.sha256) {
        Write-Warning "Hash mismatch: $($artifact.path)"
    }
}
```

## Merkle Root

```powershell
$manifest = Get-Content "C:\PatchPilot\Output\manifest.json" | ConvertFrom-Json
Write-Output "Merkle Root: $($manifest.merkleRoot)"
Write-Output "Events Chain Head: $($manifest.eventsChainHead)"
```

## Automated Verification

```powershell
Get-PatchPilotExitCodeFromEvidence -OutputRoot "C:\PatchPilot\Output"
# Verifies chain and extracts exit code from evidence only
# Implementation: src/PatchPilot.Engine/Public/Get-PatchPilotExitCodeFromEvidence.ps1
```

## Standards Compliance

Final reports include `StandardsEvidenceMap`:
- NIST SP 800-40r4: Patch lifecycle
- NIST 800-53r5: SI-2, RA-5, CM-2/3  
- CIS Controls v8: Controls 7, 12, 16

## See Also

- [Security Model](../SECURITY-COMPLIANCE/Security-Model-and-Redaction.md)
- [Audit Playbook](../SECURITY-COMPLIANCE/Audit-Playbook.md)
- [Compliance Mapping](../SECURITY-COMPLIANCE/Compliance-Mapping.md)
