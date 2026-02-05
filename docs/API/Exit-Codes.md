# PatchPilot Exit Codes

PatchPilot is **PowerShell 7 only** and is designed for **non-interactive / RMM-safe** execution.

Exit codes are deterministic and **evidence-first**: when the engine completes normally, it computes the exit code from persisted artifacts (not in-memory state).

## Exit Code Table

| Code | Meaning | Primary Source of Truth |
|------|---------|--------------------------|
| 0 | Success | `Get-PatchPilotExitCodeFromEvidence` returns Success |
| 100 | Partial Success (reserved) | Defined but not emitted by current engine logic |
| 150 | Reboot Required | Per-device reboot cookie exists **or** install-summary indicates reboot and Phase07 has not completed |
| 170 | Concurrency Lock | Per-device lock could not be acquired |
| 210 | Install Failure | `Logs\install-summary.jsonl` contains any `installed = false` |
| 220 | Validation Failure (Regression Detected) | `Reports\regressions.json` has `TotalRegressions > 0` |
| 230 | Diagnostics Failure (required) | Phase09 is `required = true` and diagnostics end with `status = Fail` |
| 240 | Reporting / Critical Failure | Unhandled exception or Phase11 attempted but `Reports\final-report.json` is missing |

## Where exit codes are defined

Exit code constants are defined in:

- `src/PatchPilot.Engine/Public/Get-PatchPilotExitCodes.ps1`

## How the engine chooses the exit code

### 1) Early return for reboot-required (150)

After Phase06 (reboot orchestration), PatchPilot may **set a per-device reboot cookie** and return **150** immediately so an RMM can schedule a reboot and re-run the tool.

This behavior occurs when:

- Phase06 produces `rebootNeeded = true`, and

- a reboot cookie is written under the per-device state root.

### 2) Evidence-first determination on normal completion

When the run completes without a thrown exception, PatchPilot returns the result of:

- `src/PatchPilot.Engine/Public/Get-PatchPilotExitCodeFromEvidence.ps1`

That function evaluates (in order):

1. **Validation regressions** (`Reports\regressions.json` → `TotalRegressions > 0` → 220)

2. **Install failures** (`Logs\install-summary.jsonl` has any `installed = false` → 210)

3. **Reboot required** (150):

   - **Primary signal:** the per-device reboot cookie exists (`DeviceStateRoot\reboot-required.json`)

   - **Secondary signal:** install-summary indicates `rebootRequired = true` AND Phase07 has not completed yet

4. **Reporting failure** (240) if Phase11 was attempted but `Reports\final-report.json` is missing

5. Otherwise **0**

### 3) Exception path and Context.ExitCode propagation

If a phase throws, `Invoke-PatchPilotRun` catches the exception and returns:

- `Context.ExitCode` if it was set by the phase (example: Phase09 required diagnostics failure → 230)

- otherwise 240

## Diagnostics failure (230)

Exit code **230** is only produced when **Diagnostics is required** and diagnostics end in failure:

- `diagnostics.required = true`

- Phase09 results in `status = Fail`

- Phase09 sets `Context.ExitCode = 230` and throws

If diagnostics are **best-effort** (`required = false`), Phase09 failures are recorded in the diagnostics summary but do **not** force a non-zero exit code.
