# Sample Output

This page shows a **sanitized example** of what PatchPilot produces after a successful run.

## Output root

PatchPilot writes evidence and artifacts under:

- `C:\ProgramData\PatchPilot\Runs\<RunId>\`

## Example layout

```text
C:\ProgramData\PatchPilot\Runs\11111111-2222-3333-4444-555555555555\
  RunSummary.json
  Events.jsonl
  Manifest.json
  Artifacts\
    Baseline\
    Snapshot\
    Diagnostics\
    UpdateCatalog\
```

## Example `RunSummary.json` (redacted)

```json
{
  "runId": "11111111-2222-3333-4444-555555555555",
  "status": "Success",
  "startedUtc": "2026-02-04T15:00:00Z",
  "endedUtc": "2026-02-04T15:04:12Z",
  "artifactsRoot": "C:/ProgramData/PatchPilot/Runs/11111111-2222-3333-4444-555555555555/Artifacts",
  "warnings": 0,
  "errors": 0
}
```
