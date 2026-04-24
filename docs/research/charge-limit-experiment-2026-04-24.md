# embercap charge-limit research — report (2026-04-24)

Companion to:

- Charter: [../superpowers/specs/2026-04-24-embercap-charge-limit-research-charter-design.md](../superpowers/specs/2026-04-24-embercap-charge-limit-research-charter-design.md)
- Plan:    [../superpowers/plans/2026-04-24-embercap-charge-limit-research-plan.md](../superpowers/plans/2026-04-24-embercap-charge-limit-research-plan.md)

All redacted artifacts for this report live under
[baseline/2026-04-24/](./baseline/2026-04-24/). Raw inputs remained
under `/tmp` and were not committed (charter R6).

---

## Phase 1 — baseline observation

- Executed on: 2026-04-24 (ISO timestamp from diag.json: `2026-04-24T13:12:55Z`)
- Branch: `main` (no research branch created this session; charter R7)
- Guardrail pre-check: `bash scripts/check-no-write-path.sh` → `ok: no write-path references in Sources/`
- `swift build`: success
- `swift test`: 22 tests passing, 0 failing
- Commands run (in order):
  1. `git status --short --branch`
  2. `swift build`
  3. `swift test`
  4. `bash scripts/check-no-write-path.sh`
  5. `.build/debug/embercap status > /tmp/embercap-baseline-status.txt`
  6. `.build/debug/embercap probe  > /tmp/embercap-baseline-probe.txt`
  7. `.build/debug/embercap diag --format=json > /tmp/embercap-baseline-diag.json`
  8. `pmset -g batt > /tmp/embercap-baseline-pmset.txt`
  9. `ioreg -rn AppleSmartBattery > /tmp/embercap-baseline-ioreg.txt`
  10. `bash scripts/redact-baseline.sh <5 raw files> docs/research/baseline/2026-04-24/`
  11. `bash scripts/verify-redaction.sh <5 raw files> docs/research/baseline/2026-04-24/`
  12. `bash scripts/check-no-write-path.sh`

- Raw paths (out of repo, not committed):
  - `/tmp/embercap-baseline-status.txt`
  - `/tmp/embercap-baseline-probe.txt`
  - `/tmp/embercap-baseline-diag.json`
  - `/tmp/embercap-baseline-pmset.txt`
  - `/tmp/embercap-baseline-ioreg.txt`

- Redacted artifacts (committed):
  - [baseline/2026-04-24/embercap-status.txt](./baseline/2026-04-24/embercap-status.txt)
  - [baseline/2026-04-24/embercap-probe.txt](./baseline/2026-04-24/embercap-probe.txt)
  - [baseline/2026-04-24/diag.json](./baseline/2026-04-24/diag.json)
  - [baseline/2026-04-24/pmset-batt.txt](./baseline/2026-04-24/pmset-batt.txt)
  - [baseline/2026-04-24/ioreg-AppleSmartBattery.txt](./baseline/2026-04-24/ioreg-AppleSmartBattery.txt)

### Observation summary

- Environment:
  - Model: `MacBookPro16,1` (expected `MacBookPro16,1`)
  - macOS: `26.4.1 (25E253)` (expected `26.4.1 (25E…)`)
  - SIP: `enabled` (expected `enabled`)
- Battery:
  - Charge percentage: `90%`
  - `isCharging`: `true`
  - `externalConnected`: `true`
  - `fullyCharged`: `false`
  - `notChargingReason`: `0`
  - `powerSourceState`: `AC Power`
  - Capacities (design/max/current, mAh): `8790/7508/6412`
  - CycleCount: `161`
  - Temperature: `30.87` °C
- Probe (from `diag.json`):
  - Verdict: `legacy-abi-unavailable`
  - `openKr`: `0` (expected `0`)
  - `openSessionKr`: `0` (expected `0`)
  - Key results (`infoKr`): `TB0T=-536870206`, `BNum=-536870206`, `BSIn=-536870206`, `BCLM=-536870206`, `CH0B=-536870206`, `CH0C=-536870206`, `CHWA=-536870206`, `CHBI=-536870206`, `CHLC=-536870206`
    (`-536870206` == `0xe00002c2` == `kIOReturnBadArgument`, consistent for all 9 legacy keys — the driver rejects the legacy selector-2 ABI uniformly on this macOS build.)

### Redaction verification

(Copied from `/tmp/embercap-baseline-verify-summary.txt`.)

```
Verify-redaction summary
------------------------
Redacted dir: docs/research/baseline/2026-04-24/
Secrets searched: 5
ok : 'F5D03110XY5K7LQC8' absent
ok : 'mbp-server' absent
ok : 'mgh3326' absent
ok : '/Users/mgh3326' absent
ok : 'mbp-server' absent
Total leaks: 0

Preservation checks
-------------------
ok : embercap-status.txt contains '%'
ok : embercap-probe.txt contains '0x'
ok : diag.json contains 'currentCapacityMAh'
ok : diag.json contains 'cycleCount'
ok : pmset-batt.txt contains '%'
ok : ioreg-AppleSmartBattery.txt contains 'CurrentCapacity'
ok : ioreg-AppleSmartBattery.txt contains 'CycleCount'
Total preservation misses: 0
```

### Incident log — redaction gap caught pre-commit (R8)

The first run of `scripts/verify-redaction.sh` against the live baseline
reported `Total leaks: 3` for the battery serial `F5D03110XY5K7LQC8`.
No redacted artifact was staged or committed while this was the case;
the verify-redaction gate aborted the flow as designed (plan Task 4
Step 4.1).

Root cause — two format mismatches between the prescribed redactor
(`scripts/redact-baseline.sh` @ `f837c95`) and this machine's actual
Phase 1 output:

1. **ioreg `"Serial"` key, capital S.** `ioreg -rn AppleSmartBattery`
   surfaces the battery serial in two places under the key name
   `"Serial"`: once as a top-level quoted entry (`"Serial" = "…"`) and
   once inside the `"BatteryData"` blob (`"Serial"="…"`, no spaces
   around `=`). The prescribed key list covered `BatterySerialNumber`,
   `"Serial Number"` (with a space), and lowercase `serial`, but not
   bare `Serial`, so both sites were missed.
2. **Column-aligned `serial` in `embercap status`.** The
   `.build/debug/embercap status` human-readable output aligns fields
   with whitespace (`serial<spaces>VALUE`), not with a colon
   (`serial: VALUE`) as the Task 1 fixtures assumed. The
   `STATUS_SERIAL_SED` rule was anchored to `serial:[[:space:]]*`, so
   the column-aligned form slipped through.

Fix — committed separately as `0822578`
(`fix(scripts): redact-baseline.sh — cover "Serial" key and column-aligned status`):

- Added bare `Serial` to the `field_scoped_sed` key chain so both
  `"Serial" = "…"` and `"Serial"="…"` (nested in `BatteryData`) are
  covered.
- Relaxed `STATUS_SERIAL_SED`'s separator class from
  `serial:[[:space:]]*` to `serial[[:space:]:]+`, accepting either a
  colon-plus-space or any run of whitespace between the key and value.

Regression check: the Task 1 fixture suite (absence + presence) was
re-run against the fixed script and still passed; the live baseline was
then re-redacted into the same output directory and
`scripts/verify-redaction.sh` reported `Total leaks: 0` /
`Total preservation misses: 0` (summary block reproduced above).

Write-path guardrail `scripts/check-no-write-path.sh` was re-run both
before the redact-baseline capture and immediately before the redacted
artifacts were staged (plan Task 4 Step 4.2); both invocations printed
`ok: no write-path references in Sources/`.

### Verdict

- Phase 1 complete. All 5 redacted artifacts + index `README.md` committed.
- `main` guardrail green before and after (`check-no-write-path.sh` and
  `swift test` both passed pre- and post-capture).
- No branch created; all work on `main` (charter R7 honored).
- Observations pinned for comparison in later phases.

### Links

- Charter §3 (safety rules), §4 (redaction), §7 (artifact conventions)
- Plan Task 3, Task 4

---

## Phase 2 — non-invasive control investigation

> Not executed in this session. See plan "Phase 2 roadmap (next session)" below.
> This section will be filled when Phase 2 is executed.

## Phase 3 — existing-tool evidence

> Not executed in this session. See plan "Phase 3 roadmap (next session)" below.

## Phase 4 — 80% mutation test

> Gated. Not authorized until charter G3→4 H1–H5 are all satisfied.
> See plan "Phase 4 roadmap (STUB)" below.

## Phase 5 — report

> Template only; see plan "Phase 5 templates".
