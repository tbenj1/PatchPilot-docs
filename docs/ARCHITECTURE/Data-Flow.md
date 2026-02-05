# Data Flow

This document describes how data moves through the 11 phases of PatchPilot.

## High-Level Flow

```mermaid
graph TD
    A[ConfigPath] -->|Read| B[Initialize-RunContext]
    B --> C[RunContext Hashtable]
    C --> D[Phase01-11]
    D --> E[Logs/, Artifacts/, Reports/]
    E -->|Re-read| F[Exit Code Computation]
    F --> G[Return Exit Code]
```

## Detailed Phase Data Flow

```mermaid
graph LR
    P01[Phase01<br/>Load Config] --> CTX[RunContext]
    CTX --> P02[Phase02<br/>Baseline]
    P02 -->|Write| B[baseline.json]
    B --> P04[Phase04<br/>Pre-Valid]
    P04 -->|Write| PV[pre-validation.json]
    PV --> P03[Phase03<br/>Catalog]
    P03 -->|Write| CAT[catalog.json]
    CAT --> P05[Phase05<br/>Install]
    P05 -->|Write| INS[install-summary.jsonl]
    INS --> P06{Phase06<br/>Reboot?}
    P06 -->|No| P07[Phase07<br/>Post-Snap]
    P06 -->|Yes| COOK[reboot.cookie]
    COOK -.Resume.-> P07
    P07 -->|Write| S[snapshot.json]
    S --> P08[Phase08<br/>Post-Valid]
    P08 -->|Write| REGR[regressions.json]
    REGR --> P09[Phase09<br/>LightDiag]
    P09 -->|Write| LightDiag[diagnostics-summary.json]
    LightDiag --> P10[Phase10<br/>Index]
    P10 -->|Write| MAN[manifest.json]
    MAN --> P11[Phase11<br/>Report]
    P11 -->|Read all| FINAL[final-report.json]
```

## Artifact Dependencies

### Phase02 → Phase07 (Snapshot Parity)

```mermaid
graph LR
    P02[Phase02] -->|Write| BASE[baseline.json<br/>categories: services,<br/>drivers, apps,<br/>updateSettings]
    P07[Phase07] -->|Write| SNAP[snapshot.json<br/>SAME categories]
    BASE -->|Input| P11
    SNAP -->|Input| P11
    P11 -->|Compute diff| DIFF[diff-report.json]
```

**Requirement:** `baseline.json` and `snapshot.json` must have **identical keys** to enable diff.

### Phase03 → Phase05 (Update Catalog)

```mermaid
graph LR
    POL[UpdatePolicy.json] -->|Read| P03[Phase03]
    P03 -->|Query COM| WU[Windows Update<br/>COM Session]
    WU -->|Filter| P03
    P03 -->|Write| CAT[catalog.json<br/>updates: [<br/> kb, title,<br/> classification,<br/> downloadSizeBytes<br/>]]
    CAT -->|Read| P05[Phase05]
    P05 -->|For each update| INST[Install via COM]
    INST -->|Append JSONL| SUMM[install-summary.jsonl]
```

### Phase04 → Phase08 (Validation)

```mermaid
graph LR
    VAL[AppValidationPolicy.json] -->|Read| P04[Phase04]
    P04 -->|Execute patterns| PRE[pre-validation.json<br/>success, confidence,<br/>evidencePath]
    VAL -->|Read again| P08[Phase08]
    P08 -->|Execute patterns| POST[post-validation.json]
    PRE -->|Compare| P08
    POST -->|Compare| P08
    P08 -->|Write| REGR[regressions.json<br/>TotalRegressions,<br/>pre/post deltas]
```

### Phase10 → Phase11 (Integrity)

```mermaid
graph LR
    ART[Artifacts/*<br/>Logs/*<br/>Reports/*] -->|Scan| P10[Phase10]
    P10 -->|SHA-256 each| IDX[artifact-index.json]
    IDX -->|Merkle root| MAN[manifest.json<br/>merkleRoot,<br/>eventsChainHead,<br/>artifactCount]
    MAN -->|Include| P11[Phase11]
    P11 -->|Write| FINAL[final-report.json<br/>integrity section]
```

## Event Flow

```mermaid
sequenceDiagram
    participant Engine as Invoke-PatchPilotRun
    participant Helper as New-EventRecord
    participant Disk as Events.jsonl

    Engine->>Helper: EngineInit
    Helper->>Disk: Genesis event (prevHash: "")
    Helper-->>Engine: Event persisted

    Engine->>Helper: PhaseStart (Phase02)
    Helper->>Disk: Event (prevHash: hash(genesis))
    Helper-->>Engine: Event persisted

    Engine->>Helper: StepStart (CaptureServices)
    Helper->>Disk: Event (prevHash: hash(PhaseStart))
    Helper-->>Engine: Event persisted

    Engine->>Helper: StepEnd (CaptureServices)
    Helper->>Disk: Event (prevHash: hash(StepStart))
    Helper-->>Engine: Event persisted

    Note over Disk: Each event chains to previous
```

**Hash Chaining:** Every event includes `prevHash` (SHA-256 of previous event's JSON).

## Exit Code Determination Flow

```mermaid
graph TD
    START[Exit Code Check] --> REGR{regressions.json<br/>TotalRegressions > 0?}
    REGR -->|Yes| E220[Exit 220]
    REGR -->|No| INST{install-summary.jsonl<br/>Any installed=false?}
    INST -->|Yes| E210[Exit 210]
    INST -->|No| REBOOT{install-summary.jsonl<br/>Any rebootRequired=true?}
    REBOOT -->|Yes| DEFER{UpdatePolicy.json<br/>deferralDays > 0?}
    DEFER -->|Yes| E150[Exit 150]
    DEFER -->|No| RPT{Phase11 attempted?}
    REBOOT -->|No| RPT
    RPT -->|Yes| FRPT{final-report.json<br/>exists?}
    FRPT -->|No| E240[Exit 240]
    FRPT -->|Yes| E0[Exit 0]
    RPT -->|No| E0
```

**Implementation:** `Invoke-PatchPilotRun.ps1` lines 249-301

**Evidence Sources:**
1. `Reports\<RunId>\regressions.json`
2. `Logs\install-summary.jsonl`
3. `examples\configs\UpdatePolicy.json`
4. `Reports\<RunId>\final-report.json`

## TestMode Flow

TestMode demonstrates evidence-first by mutating artifacts on disk:

```mermaid
graph TD
    TM[TestMode=true] --> P02[Run Phase02<br/>baseline]
    P02 --> P04[Run Phase04<br/>pre-validation]
    P04 --> INJ[Inject benign<br/>install-summary.jsonl]
    INJ --> MUT[Mutate<br/>AppValidationPolicy.json<br/>to force POST failures]
    MUT --> P08[Run Phase08<br/>post-validation]
    P08 --> REGR[regressions.json<br/>written with<br/>TotalRegressions > 0]
    REGR --> EXIT[Compute exit code<br/>by reading<br/>regressions.json]
    EXIT --> E220[Return 220]
```

**Implementation:** `Invoke-PatchPilotRun.ps1` lines 79-121

**Key Point:** TestMode does NOT set exit code in memory. It mutates artifacts, then re-reads them.

## Reboot Resume Flow

```mermaid
graph TD
    P05[Phase05 Install] --> CHK{Any update<br/>rebootRequired?}
    CHK -->|Yes| P06[Phase06]
    P06 --> PLAN[Write RebootPlan.json]
    PLAN --> COOKIE[Write reboot.cookie]
    COOKIE --> HALT[Halt execution]
    HALT --> REBOOT[System Reboots]
    REBOOT --> TASK[Scheduled Task<br/>runs Invoke-PatchPilotRun]
    TASK --> DETECT{Cookie exists?}
    DETECT -->|Yes| RESUME[Read RebootPlan.json]
    RESUME --> DEL[Delete cookie]
    DEL --> P07[Jump to Phase07]
    P07 --> P08[Phase08-11]
```

**Implementation:** `Invoke-PatchPilotRun.ps1` lines 125-148

**Artifacts:**
- `State\RebootPlan.json` - Stores `nextPhase`, `returnPath`, `timestamp`
- `State\reboot.cookie` - Marker file for detection

## Data Persistence Guarantees

| Phase | Persisted Artifact | Encoding | Hash | Read By |
|-------|-------------------|----------|------|---------|
| 01 | `State\state.json` | UTF-8 no BOM | - | Resume logic |
| 02 | `Artifacts\Baseline\<RunId>\baseline.json` | UTF-8 no BOM | SHA-256 | Phase11 |
| 03 | `Artifacts\UpdateCatalog\<RunId>\catalog.json` | UTF-8 no BOM | SHA-256 | Phase05 |
| 04 | `Reports\<RunId>\pre-validation.json` | UTF-8 no BOM | SHA-256 | Phase08, Phase11 |
| 05 | `Logs\install-summary.jsonl` | UTF-8 no BOM | SHA-256 | Exit code logic, Phase11 |
| 06 | `State\RebootPlan.json`, `State\reboot.cookie` | UTF-8 no BOM | - | Resume logic |
| 07 | `Artifacts\Snapshot\<RunId>\snapshot.json` | UTF-8 no BOM | SHA-256 | Phase11 |
| 08 | `Reports\<RunId>\regressions.json` | UTF-8 no BOM | SHA-256 | Exit code logic, Phase11 |
| 09 | `Artifacts\Diagnostics\LightDiag\<RunId>\diagnostics-summary.json` | UTF-8 no BOM | SHA-256 | Phase11 |
| 10 | `artifact-index.json`, `manifest.json` | UTF-8 no BOM | - | Phase11, auditors |
| 11 | `Reports\<RunId>\final-report.json` | UTF-8 no BOM | SHA-256 | Exit code logic, external tools |

**All Phases:** `Logs\Events.jsonl` (hash-chained, read by Phase10 for `eventsChainHead`)

## Summary

Data flows through PatchPilot in a **unidirectional, append-only** manner:
1. Phases **write** artifacts to disk immediately
2. Subsequent phases **read** artifacts (never assume in-memory state)
3. Exit codes are **computed** by re-reading artifacts (evidence-first)
4. Integrity is **verified** via hash chains (events) and Merkle roots (artifacts)

**No shortcuts.** All decisions trace to persisted evidence.

## References

- [Architecture Overview](Architecture.md)
- [Phases](Phases.md)
- [Evidence-First](Evidence-First.md)
- [Artifacts & Schemas](../API/Artifacts-and-Schemas.md)
