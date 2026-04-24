# embercap Charge-Limit Research Charter (2026-04-24)

Status: **active research charter**. Governs a multi-phase, evidence-driven
experiment that determines whether this Mac can be made to stop charging below
100% without adding write-path code to `main`, without modifying SIP, and
without installing privileged helpers.

This charter is the companion governance document for the plan at
`docs/superpowers/plans/2026-04-24-embercap-charge-limit-research-plan.md`
and the research report at
`docs/research/charge-limit-experiment-2026-04-24.md`.

Target machine is the same as the existing read-only diagnostic CLI spec at
`docs/superpowers/specs/2026-04-23-embercap-read-only-diag-cli-design.md` §2.
That spec's "`main` is read-only" posture is an input constraint here, not a
negotiable assumption.

## 1. Purpose & scope

### 1.1 Research question

Can the target machine be made to stop charging below 100% (initial target:
**80%**) using a practical userland method on this macOS version, without
modifying SIP, without installing privileged helpers or KEXTs, and without
adding write-path code to `main`?

### 1.2 In-scope phases

- **Phase 1** — read-only baseline observation on `main`.
- **Phase 2** — non-invasive control-surface investigation (next session).
- **Phase 3** — existing-tool evidence collection, observation-only (next
  session).
- **Phase 4** — a single reversible 80% charge-limit test, gated.
- **Phase 5** — report, in one of two templates (5a success / 5b negative).

"Mutation" in this charter, and specifically the "Phase 4 mutation" wording
in §5 and §6, means applying a **public or semi-public control surface**
whose existence, effect, and reset path were confirmed in Phase 2 or Phase
3 — for example, a documented `pmset` option, a writable IOKit property
exposed to userland, or a configuration flip performed by a pre-existing
third-party tool whose behavior on this OS is already documented.
It does **not** mean and never authorizes an SMC or IOKit *write* call via
the legacy `AppleSMC` userclient or any equivalent private dispatch. R1
binds Phase 4 exactly as strictly as every other phase.

### 1.3 Out-of-scope (invariant)

- SMC/IOKit write attempts from any branch.
- SIP modification.
- Privileged helper, daemon, or KEXT installation.
- Write-path code in `main`.
- Generalization to M-series Apple Silicon or other Intel models.
- Reverse-engineering the modern `AppleSMCClient` private dispatch (already
  out-of-scope per the read-only diag CLI spec §4).
- Simultaneous experimentation with multiple target percentages. Initial test
  target is 80% only; 75%/70% are follow-ups considered only after an 80%
  result is reproducible.

## 2. Target machine & environment

- Model: MacBookPro16,1 (Intel Core i9-9880H).
- macOS: 26.4.1 (build pinned from `embercap diag` in the Phase 1 report).
- SIP: enabled.
- Embercap version and commit SHA pinned from `embercap version` / `embercap
  diag` in the Phase 1 report.

Any future phase must re-verify the environment before executing. A mismatch
is grounds for aborting that phase under the environment re-verification
gate and the charter safety rules in §3 as a whole. R4 specifically
governs the `main` write-path guardrail, not environment identity.

## 3. Invariant safety rules

These rules hold across every phase and every branch.

- **R1** No SMC/IOKit write attempts. No calls to `IOConnectCallStructMethod`
  with `selector=6`, `kSMCWriteKey`, or any selector that mutates SMC state.
  This rule applies to every phase, including Phase 4. The "Phase 4
  mutation" wording elsewhere in this charter refers exclusively to
  public/semi-public control surfaces confirmed in Phase 2 or Phase 3; see
  the terminology note in §1.2.
- **R2** No SIP modification. `csrutil` is consulted read-only.
- **R3** No installation of privileged helpers, daemons, or KEXTs. Existing
  installations may be *observed* (file system, LaunchDaemon listing,
  Preferences). They are never *started*, *loaded*, *registered*, or
  *upgraded* by this research.
- **R4** `main` remains read-only. `scripts/check-no-write-path.sh` must pass
  before and after every phase that touches the repo.
- **R5** Any mutation step requires both phase gate G3→4 all-green AND
  explicit written user approval in the session that performs the mutation.
  Mutation is forbidden otherwise.
- **R6** Raw dumps are never committed to the repository. Only redacted
  artifacts may be committed. Redaction rules are §4.
- **R7** No research branch or worktree is created during the 2026-04-24
  session. Phase 1 runs directly on `main` because all Phase 1 commands are
  read-only (observation-only CLIs and system queries).
- **R8** Failures and errors are preserved, not hidden. Raw `kern_return_t`
  values, non-zero exit codes, and unexpected output are reported verbatim.

## 4. Disclosure & redaction policy

### 4.1 Mask (redact) targets

Values that identify the specific physical device or user:

- `embercap diag` (`diag.json`) fields:
  - `battery.serial` (top-level string value).
  - `machine.kernel` — the second whitespace token of the `uname -a` string
    is the host's short hostname; mask only that token.
- `ioreg` fields (per-line match on field name):
  - `BatterySerialNumber`
  - `Serial Number` / `Hardware Serial Number`
  - `IOPlatformSerialNumber` / `PlatformSerialNumber`
  - `IOPlatformUUID`
  - `UUID` — matched only as an exact whole field name (i.e. a line whose
    key is the single token `"UUID"` followed by `=`). Substrings of other
    key names such as `kIOSomethingUUIDKey` are never matched.
  - `MACAddress` / `IOMACAddress` (if emitted)
- Host environment, anywhere in any artifact:
  - Unix username (`$USER`).
  - Home directory path `/Users/$USER/...` → `/Users/<USER-REDACTED>/...`.
  - Local hostname (`scutil --get LocalHostName`) and the short form returned
    by `hostname`.

Mask placeholders (fixed strings):

- `<SERIAL-REDACTED>`
- `<UUID-REDACTED>`
- `<HOSTNAME-REDACTED>`
- `<USER-REDACTED>`
- `<MAC-REDACTED>`

### 4.2 Preserve (do NOT redact) targets

Diagnostic and numeric values required for cross-phase comparison must be
preserved byte-for-byte:

- Battery state: `CurrentCapacity`, `MaxCapacity`, `DesignCapacity`,
  `CycleCount`, `DesignCycleCount9C`.
- Electrical: `Voltage`, `Amperage`, `InstantAmperage`.
- Thermal: `Temperature`.
- State flags: `IsCharging`, `FullyCharged`, `ExternalConnected`,
  `ExternalChargeCapable`, `AtCriticalLevel`, `AtWarnLevel`,
  `isPresent`, `isCharged`, `powerSourceState`.
- Reason strings: `NotChargingReason` string form and the numeric
  equivalent.
- IOKit return values: the full `IOReturn` hex such as `0xe00002c2`
  (`kIOReturnBadArgument`), signed-32 forms (`-536870206`), `kern_return_t`
  values, `mach_error_string` outputs, and selector numbers (`selector=0`,
  `selector=2`, etc.).
- Symbolic names: function names, IOKit class names (`AppleSMC`,
  `AppleSMCClient`, `AppleSmartBattery`), SMC key four-char codes (`TB0T`,
  `BNum`, `BCLM`, `CH0B`, `CH0C`, `CH0I`, `CH0J`, `CH0K`, `CHWA`, etc.).
- Environment metadata: `sw_vers` product/version/build strings, kernel
  version *excluding* the hostname token, CPU brand string, architecture
  (`x86_64`), SIP status.

### 4.3 Scope rule

Redaction is **field-scoped**. Only values of the specific fields listed in
§4.1, plus `$USER` / home path / hostname literals, are masked. Raw hex
return codes (`0x…`) and selector numbers are **never** masked, regardless
of length or appearance.

A long hex string is masked only when it is the value of a mask-target
field. A long hex string that is, for example, a commit SHA (`commitSHA`
field in `diag.json`), a Mach port number, or an address in an error
message, is **not** masked.

### 4.4 Redaction implementation

`scripts/redact-baseline.sh` applies the rules via explicit field-scoped
`sed` patterns. The script:

- takes explicit file arguments (no globs);
- writes redacted outputs into a named target directory;
- performs no system mutation of any kind;
- also emits a `README.md` index in the target directory listing the inputs,
  the placeholders, and a link to this charter §4.

### 4.5 Verification (before commit)

After redaction, a verification step is run against the committed artifacts
before the commit. `scripts/verify-redaction.sh` must both:

- **Absence check** — grep the redacted outputs for:
  - the live `$USER` value,
  - the live `scutil --get LocalHostName` value,
  - the live `hostname` value,
  - the literal string of `battery.serial` taken from the raw
    `/tmp/embercap-baseline-diag.json` input,
  - the literal string of `IOPlatformSerialNumber` / `IOPlatformUUID` taken
    from the raw ioreg input;

  all counts must be 0.
- **Presence check** — confirm each artifact still contains at least one
  preserved diagnostic value:
  - `diag.json` contains a `CurrentCapacity` or `currentCapacityMAh` key;
  - `ioreg-AppleSmartBattery.txt` contains `CurrentCapacity` and
    `CycleCount` lines;
  - `embercap-probe.txt` contains at least one `0x` hex return code or a
    `mach_error_string` token;
  - `embercap-status.txt` contains the charge percentage;
  - `pmset-batt.txt` contains a percentage token.

The verification summary (all absence counts, all presence hits) is copied
into the Phase 1 report. If any absence count is non-zero, nothing is
committed; the script exits non-zero and a charter-level incident is logged
in the report.

## 5. Phase transition gates

- **G1→2** — trivial. Phase 1 baseline has been collected, all redacted
  artifacts committed, verification summary green, `main` guardrail green
  before and after. Phase 2 may proceed.
- **G2→3** — conditional on Phase 2 outcome but not blocking:
  - If Phase 2 identifies ≥1 concrete candidate control property, Phase 3
    proceeds with objective "verify candidate via existing-tool evidence".
  - If Phase 2 identifies 0 candidates, Phase 3 still proceeds, but with
    objective narrowed to "find existing-tool evidence of a working control
    on this OS".
  - In both cases, Phase 3 executes. Phase 2 emptiness alone does not abort.
- **G3→4** — **hard gate. All of the following must be true before any
  mutation step:**
  - **H1** ≥1 concrete control candidate identified (specific property key,
    command, or tool-operation evidence) from Phase 2 or Phase 3.
  - **H2** Reversible reset path documented (exact commands, or a
    reboot/SMC-reset fallback with expected behavior and explicit risks).
  - **H3** Explicit written user approval to execute Phase 4, recorded in
    the session that will execute it.
  - **H4** `main` guardrail green re-checked immediately before mutation. If
    broken at any point during Phase 4, Phase 4 aborts immediately.
  - **H5** Raw-vs-redacted artifact policy re-confirmed: all Phase 1–3 raw
    dumps remain outside the repo; only redacted artifacts are tracked.
- **G4→5** — record. Phase 4 outcome (worked / partial / failed / aborted)
  is written into Phase 5a or 5b regardless of outcome. No outcome is
  silently dropped (R8).

## 6. Abort-to-negative-result conditions

Abort to Phase 5b (negative-result documentation) if any one of the
following holds:

- **A(2∧3-empty)** — (Phase 2 identifies 0 concrete candidates) AND
  (Phase 3 finds 0 existing-tool operation evidence on this OS).
- **A(H1-unmet)** — G3→4 H1 unmet at the mutation authorization moment.
- **A(H2-unmet)** — G3→4 H2 unmet at the mutation authorization moment.

Phase 2 returning 0 candidates alone does NOT abort (Phase 3 still runs).
Phase 3 returning 0 evidence alone does NOT abort if Phase 2 produced a
candidate. Only the combined emptiness A(2∧3-empty), or an H1/H2 unmet at
the mutation gate, triggers negative-result.

H4 broken mid-execution is an immediate abort of Phase 4 regardless of any
other condition, under R4.

On abort to 5b:

- No mutation is attempted.
- The Phase 5b report summarizes evidence collected and cites artifacts.
- A follow-up task is recorded to add a one-line reference in `README.md`
  and/or the existing read-only diag CLI spec noting "2026-04-24 follow-up
  confirmed negative-result".

## 7. Artifact conventions

### 7.1 Directory layout

```
docs/
  research/
    charge-limit-experiment-2026-04-24.md        (phase-by-phase report)
    baseline/
      2026-04-24/
        README.md                                (index)
        embercap-status.txt                      (redacted)
        embercap-probe.txt                       (redacted)
        diag.json                                (redacted JSON)
        pmset-batt.txt                           (redacted)
        ioreg-AppleSmartBattery.txt              (redacted)
  superpowers/
    specs/2026-04-24-embercap-charge-limit-research-charter-design.md
    plans/2026-04-24-embercap-charge-limit-research-plan.md
scripts/
  redact-baseline.sh                             (explicit-file redaction)
  verify-redaction.sh                            (absence + presence checks)
  check-no-write-path.sh                         (unchanged, still binding)
```

Phase 2 and Phase 3 artifact directories follow the same pattern:
`docs/research/phase2/2026-04-24/` and `docs/research/phase3/2026-04-24/`,
each with its own `README.md` index. Their artifacts must pass the same
redaction + verification pipeline.

### 7.2 Report section template

Each phase section in `docs/research/charge-limit-experiment-2026-04-24.md`
uses the following structure:

```
### Phase N — <name>
- Executed on: <ISO date>
- Commands run: <exact list>
- Raw paths (out-of-repo): </tmp/... paths>
- Redacted artifacts: <docs/research/... paths>
- Observation summary: <bullet list of observation targets with values>
- Redaction verification: <absence counts, presence hits>
- Verdict: <one line>
- Links: <charter §; plan phase link>
```

### 7.3 Document relationships

- **Charter (this document)** — invariants, gates, policy. Rarely changes.
  A change here requires an explicit revision note.
- **Plan** — ordered execution blueprint. Updated as phases are completed.
- **Research report** — growing record. Filled phase by phase.

## 8. Deliverables checklist

- **D1** This charter.
- **D2** Plan document at the path in §7.1.
- **D3** Phase 1 baseline artifacts: 5 redacted files + `README.md` under
  `docs/research/baseline/2026-04-24/`.
- **D4** `scripts/redact-baseline.sh` and `scripts/verify-redaction.sh`
  committed.
- **D5** Phase 1 section of `docs/research/charge-limit-experiment-2026-04-24.md`
  filled with observation summary and redaction verification summary.
- **D6** `main` guardrail green: `bash scripts/check-no-write-path.sh` and
  `swift test` passing before and after Phase 1. Evidence cited in the
  report.

## 9. Non-goals (explicit exclusions)

- Reverse-engineering the modern `AppleSMCClient` dispatch (out-of-scope per
  the existing read-only diag CLI spec §4).
- Generalization to M1/M2/M3 Apple Silicon Macs or other Intel models.
- Simultaneous experimentation with multiple target percentages.
- Any behavior that requires prompting the user for their administrator
  password during Phase 1–3 observation.
- Any cloud upload or external publication of raw (non-redacted) artifacts.
