# Troubleshooting

This guide focuses on **non-interactive / RMM-safe** troubleshooting using persisted evidence artifacts.

## 1) Determine the RunRoot

Each execution writes to:
- `OutputRoot\Runs\<RunId>\...`

If you know the OutputRoot but not the RunId, you can pick the most recent run folder:

```powershell
$OutputRoot = 'C:\PatchPilot\Output'
$RunRoot = Get-ChildItem -Path (Join-Path $OutputRoot 'Runs') -Directory | Sort-Object LastWriteTimeUtc | Select-Object -Last 1 | Select-Object -ExpandProperty FullName
$RunRoot
```

## Execution policy / unsigned module import

If you see an error similar to:

> `... cannot be loaded ... is not digitally signed. You cannot run this script ...`

For **local development/testing**, use a process-scope bypass and remove Mark-of-the-Web (MOTW) if the repo was downloaded as a zip:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
Get-ChildItem -Recurse -File | Unblock-File -ErrorAction SilentlyContinue
```

If your environment enforces `AllSigned` by Group Policy, you must run a **signed** build with a trusted code-signing certificate.

## RMM `-Command` quoting pitfalls

If you see an error like:

> `A positional parameter cannot be found that accepts argument 'C:\Users\...\PatchPilot\'`

it is typically caused by nested quoting/escaping in `pwsh -Command` invocations. Use the validated patterns in:

- [Local Execution & Validation](Local-Execution-and-Validation.md)

## 2) Reboot loops / reboot required (exit code 150)

PatchPilot uses a **per-device reboot cookie** to coordinate reboot/resume.

- Cookie location (per-device state root):
  - `OutputRoot\State\Tenants\<TenantId>\Clients\<ClientId>\Sites\<SiteId>\Devices\<DeviceId>\reboot-required.json`

If the cookie exists, PatchPilot will report reboot required on the next run until it is consumed.

## 3) Install failures (exit code 210)

Inspect the install summary JSONL:
- `RunRoot\Logs\install-summary.jsonl`

Example:

```powershell
$Install = Get-Content (Join-Path $RunRoot 'Logs\install-summary.jsonl') | ForEach-Object { $_ | ConvertFrom-Json }
$Install | Where-Object { -not $_.installed } | Select-Object kb, title, hresult, rebootRequired
```

## 4) Validation regressions (exit code 220)

Regressions are reported in:
- `RunRoot\Reports\regressions.json`

Example:

```powershell
$Reg = Get-Content (Join-Path $RunRoot 'Reports\regressions.json') -Raw | ConvertFrom-Json
$Reg.TotalRegressions
$Reg.Regressions | Select-Object app, checkName, preStatus, postStatus
```

## 5) Diagnostics / LightDiag (exit code 230 only when required)

Diagnostics summary (Phase09):
- `RunRoot\Artifacts\Diagnostics\LightDiag\<RunId>\diagnostics-summary.json`

Example:

```powershell
$RunId = Split-Path $RunRoot -Leaf
$DiagSummaryPath = Join-Path $RunRoot "Artifacts\Diagnostics\LightDiag\$RunId\diagnostics-summary.json"
$Diag = Get-Content $DiagSummaryPath -Raw | ConvertFrom-Json
$Diag.status
$Diag.triggeredBy
$Diag.collectors | Select-Object name, status, artifacts, bytes
```

Common reasons for diagnostics failure/partial results include:
- `capExceeded = true` (size/runtime caps were hit)
- Access/permission issues reading logs/files
- Collector disabled in the config (reported as `Skipped`)

## 6) Concurrency lock (exit code 170)

PatchPilot uses a **per-device lock** to prevent concurrent runs for the same device identity.

Lock file location:
- `OutputRoot\State\Tenants\<TenantId>\Clients\<ClientId>\Sites\<SiteId>\Devices\<DeviceId>\lock.json`

If a lock is stale, the engine may remove it when TTL rules are met (see config `lockTtlMinutes`).

## 7) Reporting failure (exit code 240)

If Phase11 was attempted but no final report exists, check:
- `RunRoot\Reports\final-report.json`
- `RunRoot\Logs\Events.jsonl` (PhaseEnd events)

A thrown exception without a phase-specific `Context.ExitCode` also returns 240.
