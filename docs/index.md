# PatchPilot Documentation

**Evidence-First Patch Validation for MSPs**

PatchPilot is a PowerShell 7 patch orchestration engine designed for multi-tenant MSP environments. It provides deterministic, auditable patch management with built-in compliance mapping and regression detection.

## Quick Navigation

- **New to PatchPilot?** Start with the [Quickstart Guide](GUIDES/Quickstart.md)
- **Want the big picture?** Read the [Leadership Brief](PRODUCT/Leadership-Brief.md)
- **Need to run a patch cycle?** Follow the [Runbook](OPERATIONS/Runbook-Patch-Cycle.md)
- **Troubleshooting?** Check the [Troubleshooting Guide](OPERATIONS/Troubleshooting.md)
- **Audit or compliance review?** See [Compliance Mapping](SECURITY-COMPLIANCE/Compliance-Mapping.md)

## What is PatchPilot?

PatchPilot orchestrates Windows patching across 11 phases with these guarantees:

- **Evidence-First**: All decisions derive from persisted artifacts (never in-memory state)
- **Deterministic Exit Codes**: Machine-readable outcomes for RMM/automation (0, 100, 150, 170, 210, 220, 230, 240)
- **Safe Resume**: Survives reboots via persistent checkpointing
- **Integrity Chains**: SHA-256 hash chaining for events; Merkle roots for artifacts
- **Compliance-Ready**: Maps evidence to NIST SP 800-40r4, NIST 800-53r5, CIS Controls v8

## Core Concepts

### 11 Phases

1. **Phase01** - Initialization
2. **Phase02** - Baseline Snapshot
3. **Phase03** - Update Classification Fetch
4. **Phase04** - Pre-Validation
5. **Phase05** - Patch Install
6. **Phase06** - Reboot Orchestration
7. **Phase07** - Post-Snapshot
8. **Phase08** - Post-Validation
9. **Phase09** - Diagnostics/LightDiag
10. **Phase10** - Evidence Indexing
11. **Phase11** - Reporting

### Evidence Artifacts

All evidence is written to `OutputRoot\` with UTF-8 encoding (no BOM):

- `Logs\Events.jsonl` - Hash-chained event log
- `Logs\install-summary.jsonl` - Per-update install outcomes
- `Artifacts\Baseline\<RunId>\baseline.json` - Pre-patch snapshot
- `Artifacts\Snapshot\<RunId>\snapshot.json` - Post-patch snapshot
- `artifact-index.json` - SHA-256 index of all artifacts
- `manifest.json` - Merkle root + events chain head

### Entry Point

```powershell
Invoke-PatchPilotRun `
  -OutputRoot 'C:\PatchPilot\Output' `
  -ConfigPath 'C:\PatchPilot\Config\ClientProfile.json' `
  -TenantId 'MSP001' `
  -ClientId 'ACME'
```

See [PowerShell Module Reference](API/PowerShell-Module-Reference.md) for details.

## Documentation Structure

### Architecture
- [Overview](ARCHITECTURE/Architecture.md) - System design and principles
- [Phases](ARCHITECTURE/Phases.md) - 11-phase pipeline
- [Evidence-First](ARCHITECTURE/Evidence-First.md) - Why evidence drives decisions
- [Data Flow](ARCHITECTURE/Data-Flow.md) - How data moves through phases

### API
- [PowerShell Module Reference](API/PowerShell-Module-Reference.md)
- [Exit Codes](API/Exit-Codes.md)
- [Artifacts & Schemas](API/Artifacts-and-Schemas.md)

### Operations
- [User Guide](OPERATIONS/User-Guide.md)
- [Runbook (Patch Cycle)](OPERATIONS/Runbook-Patch-Cycle.md)
- [Troubleshooting](OPERATIONS/Troubleshooting.md)
- [Evidence Verification](OPERATIONS/Evidence-Verification.md)
- [RMM Integration](OPERATIONS/RMM-Integration.md)
- [ITSM / Change Control](OPERATIONS/ITSM-ChangeControl.md)

### Security & Compliance
- [Compliance Mapping](SECURITY-COMPLIANCE/Compliance-Mapping.md)
- [Audit Playbook](SECURITY-COMPLIANCE/Audit-Playbook.md)
- [Security Model & Redaction](SECURITY-COMPLIANCE/Security-Model-and-Redaction.md)
- [Data Retention](SECURITY-COMPLIANCE/Data-Retention.md)

### Product
- [Leadership Brief](PRODUCT/Leadership-Brief.md)
- [Value for MSPs](PRODUCT/Value-For-MSPs.md)
- [Roles & RACI](PRODUCT/Roles-and-RACI.md)
- [KPIs / OKRs / ROI](PRODUCT/KPIs-OKRs-ROI.md)
- [Roadmap](PRODUCT/Roadmap.md)

### Testing & Quality
- [Test Strategy](TESTING-QUALITY/Test-Strategy.md)
- [Determinism & TestMode](TESTING-QUALITY/Determinism-and-TestMode.md)
- [CI/CD Guide](TESTING-QUALITY/CI-CD-Guide.md)

### Guides
- [Quickstart](GUIDES/Quickstart.md)
- [Policy Authoring](GUIDES/Policy-Authoring.md)
- [Examples & Scenarios](GUIDES/Examples-and-Scenarios.md)

### Appendices
- [Directory Layout](APPENDICES/Directory-Layout.md)
- [JSON Examples](APPENDICES/JSON-Examples.md)
- [Glossary](APPENDICES/Glossary.md)
- [Change Record Template](APPENDICES/Change-Record-Template.md)
- [Demo Script](APPENDICES/Demo-Script.md)

### Diagrams
- [System Diagrams](DIAGRAMS/Diagrams.md)

## Repository Structure

```
PatchPilotv3/
├── src/
│   └── PatchPilot.Engine/
│       ├── Public/               # Invoke-PatchPilotRun, Get-PatchPilotExitCodes, etc.
│       └── Private/              # Phase functions, helpers
├── data/
│   └── schemas/                  # JSON Schemas for all artifacts
├── examples/
│   └── configs/                  # UpdatePolicy.json, AppValidationPolicy.json, diagnostics config (top-level "diagnostics" block)
├── tests/                        # Pester tests (StageC–StageI)
└── docs/                         # This documentation
```

## Getting Started

1. **Install PowerShell 7** (required)
2. **Import the module**: `Import-Module .\src\PatchPilot.Engine\PatchPilot.Engine.psd1`
3. **Run demo**: See [Demo Script](APPENDICES/Demo-Script.md)
4. **Explore exit codes**: `Get-PatchPilotExitCodes`

## License

(Vendor-neutral, open documentation)

---

**Questions?** See [Troubleshooting](OPERATIONS/Troubleshooting.md) or [Glossary](APPENDICES/Glossary.md)
