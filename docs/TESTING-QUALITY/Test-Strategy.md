# Test Strategy

## Overview

PatchPilot documentation for TESTING-QUALITY.

**Referenced artifacts:**
- Module: `src/PatchPilot.Engine/PatchPilot.Engine.psd1`
- Functions: `src/PatchPilot.Engine/Public/*.ps1`
- Configs: `examples/configs/*.json`
- Schemas: `data/schemas/*.schema.json`
- Tests: `tests/*.Tests.ps1`

## Key Concepts

Documentation content for Test Strategy.

## See Also

- [User Guide](../OPERATIONS/User-Guide.md)
- [Runbook](../OPERATIONS/Runbook-Patch-Cycle.md)
- [Troubleshooting](../OPERATIONS/Troubleshooting.md)

---

## Pester-loaded sessions and masking risk

Some historical failures were only visible in real non-TestMode runs, while unit tests passed.

**Rule:** Validation must include at least one **clean non-TestMode run** from a fresh `pwsh -NoProfile` process.

Recommended verification:

- Run the *Full local real run (non-TestMode) + validation* script from **Operations → Local Execution & Validation**.
- Repeat once with `Import-Module Pester -Force` in the same session.
- Compare outcomes (exit code, presence of `catalog.json`, and absence of error signatures in `Logs/Events.jsonl`).

