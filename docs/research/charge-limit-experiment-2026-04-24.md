# embercap charge-limit research — report (2026-04-24)

Companion to:

- Charter: [../superpowers/specs/2026-04-24-embercap-charge-limit-research-charter-design.md](../superpowers/specs/2026-04-24-embercap-charge-limit-research-charter-design.md)
- Plan:    [../superpowers/plans/2026-04-24-embercap-charge-limit-research-plan.md](../superpowers/plans/2026-04-24-embercap-charge-limit-research-plan.md)

Redacted artifacts for this report live under
[baseline/2026-04-24/](./baseline/2026-04-24/) (Phase 1) and
[phase2/2026-04-25/](./phase2/2026-04-25/) (Phase 2). Raw inputs
remained under `/tmp` and were not committed (charter R6).

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
Secrets searched: 6
ok : battery.serial absent
ok : kernel.hostname absent
ok : ioreg.Serial absent
ok : live.USER absent
ok : live.home-path absent
ok : live.hostname absent
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

The verify-redaction output now names only the *category* of each
checked secret (e.g. `battery.serial`, `kernel.hostname`,
`ioreg.Serial`, `live.USER`), never the secret value itself. See the
2026-04-25 addendum to the incident log below for the structural fix
that made this possible.

### Incident log — redaction gap caught pre-commit (R8)

The first run of `scripts/verify-redaction.sh` against the live baseline
reported `Total leaks: 3` for the `ioreg.Serial` category (the live
battery serial surfaced uncovered at two sites in the ioreg dump and at
one site in the column-aligned `embercap status` output). No redacted
artifact was staged or committed while this was the case; the
verify-redaction gate aborted the flow as designed (plan Task 4
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

### Incident log addendum — 2026-04-25 redaction-pipeline hardening

Post-commit review of the Phase 1 artifacts (commits `3fc337e`,
`8267226`) surfaced two further charter-policy gaps. Neither is a
privacy escalation relative to pre-existing disclosures in
`docs/samples/` and the prior read-only-diag spec, but both are policy
violations under this charter and were remediated before any push to
`origin/main`.

A. **`scripts/verify-redaction.sh` self-disclosed secret values in its
   `ok : … absent` lines** (`ok : '<value>' absent`). When the summary
   block was pasted into this report verbatim, the live
   `battery.serial`, hostname, username, and home path appeared as
   plain text. Violates charter §4.1.

B. **`scripts/redact-baseline.sh` `KERNEL_HOST_SED` over-matched** the
   second `Darwin <token>` occurrence in `uname -a` output, replacing
   the literal word `Kernel` in `Darwin Kernel Version …` with
   `<HOSTNAME-REDACTED>`. Violates charter §4.2, which preserves the
   kernel-version string *excluding* the hostname token.

Fixes (committed alongside this addendum):

A. `verify-redaction.sh` refactored to a parallel `SECRETS[]` /
   `LABELS[]` design. Absence and leak lines now print the category
   label (`battery.serial`, `kernel.hostname`, `ioreg.Serial`,
   `live.USER`, `live.home-path`, `live.hostname`, and the optional
   `ioreg.BatterySerialNumber` / `ioreg.IOPlatformUUID` /
   `ioreg.IOPlatformSerialNumber` when present) and never the value.
   Task 2 fixture suite re-run: happy-path exit 0, sad-path exit 1,
   plus an explicit assertion that the fixture secret and hostname do
   not appear on stdout.

B. `redact-baseline.sh` `KERNEL_HOST_SED` is now anchored on a
   following whitespace + version triplet
   (`[[:space:]]+[0-9]+\.[0-9]+\.[0-9]+`), which in `uname -a` follows
   only the hostname and never the `Kernel` literal. Task 1 fixture
   suite re-run and still passes, including a new explicit assertion
   that `Darwin Kernel Version` survives in the redacted kernel line.

Remediation applied to this report and the baseline dir:

- The "Redaction verification" block above was replaced with the
  regenerated, label-only summary produced by the fixed verifier.
- The literal battery serial previously quoted in the root-cause
  section has been replaced with the category reference
  `ioreg.Serial`.
- The Phase 1 `diag.json` artifact was regenerated from the same
  `/tmp/embercap-baseline-diag.json` raw input using the fixed
  redactor; the kernel line now reads
  `"Darwin <HOSTNAME-REDACTED> 25.4.0 Darwin Kernel Version 25.4.0: …"`.
  All four other redacted artifacts are byte-identical to the prior
  commit — no observational drift was introduced, since the raw
  `/tmp` inputs from the 2026-04-24 capture were re-used verbatim.

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

- Executed on: 2026-04-25 (raw capture window 03:13–06:31 KST; redaction
  pipeline finalized later the same day during this Phase 2 wrap-up
  session, after the redactor extension below).
- Branch: `main` (no research branch created; charter R7).
- Pre-Phase-2 commit: Phase 1 wrap commit `57a170f`
  (`research(phase1): sanitize report and regenerate baseline diag.json
  after pipeline fix`). Working tree was clean at the start of the
  Phase 2 capture (modulo new untracked Phase 2 paths).
- Pre-Phase-2 charge state (from a fresh `embercap diag --format=json`
  run at the start of capture, raw stored at
  `/tmp/embercap-pre-phase2-diag.json` — not committed): `100%` /
  `isCharging=false` / `fullyCharged=true` / `externalConnected=true` /
  `notChargingReason` and `powerSourceState` reported as the
  `AC Power, Not Charging` steady state. This differs from the Phase 1
  capture (`90%, charging`); the natural overnight charge-up is the
  intended explanation.
- Guardrail pre-check (`bash scripts/check-no-write-path.sh`):
  `ok: no write-path references in Sources/`.
- `swift test`: 22 tests passing, 0 failing (same as Phase 1).

### Commands run (read-only)

In order:

```bash
mkdir -p /tmp/embercap-phase2

pmset -g custom                          > /tmp/embercap-phase2/pmset-custom.txt
pmset -g rawlog                          > /tmp/embercap-phase2/pmset-rawlog.txt
pmset -g assertions                      > /tmp/embercap-phase2/pmset-assertions.txt
ioreg -l -w0 -r -c AppleSmartBattery     > /tmp/embercap-phase2/ioreg-AppleSmartBattery-full.txt
ioreg -l -w0 -p IOService -n AppleSMC    > /tmp/embercap-phase2/ioreg-AppleSMC-full.txt
defaults read com.apple.PowerManagement  > /tmp/embercap-phase2/power-prefs.txt 2>/tmp/embercap-phase2/power-prefs.stderr || true

bash scripts/redact-phase2.sh /tmp/embercap-phase2 docs/research/phase2/2026-04-25
bash scripts/check-no-write-path.sh
swift test
```

`pmset -g rawlog` is a long-running stream; per the `pmset(1)` contract
it writes one polled-status line per minute and a notification line on
each power-source change. The earlier Phase 2 attempt left this command
running until interrupted; the recovery session for which this section
was written reused the captured 42 KB sample (lines 1..584,
`/tmp/embercap-phase2/pmset-rawlog.txt`, covering 2026-04-25 03:19–06:31
KST) rather than re-running the stream.

### Raw paths (out of repo, not committed; charter R6)

- `/tmp/embercap-phase2/pmset-custom.txt`               (1.0 KB, 43 lines)
- `/tmp/embercap-phase2/pmset-rawlog.txt`               (42 KB,  584 lines)
- `/tmp/embercap-phase2/pmset-assertions.txt`           (1.0 KB, 20 lines)
- `/tmp/embercap-phase2/ioreg-AppleSmartBattery-full.txt` (12 KB, 56 lines)
- `/tmp/embercap-phase2/ioreg-AppleSMC-full.txt`        (3.9 MB, 19705 lines)
- `/tmp/embercap-phase2/power-prefs.txt`                (0 bytes, empty stdout)
- `/tmp/embercap-phase2/power-prefs.stderr`             (97 B, "Domain com.apple.PowerManagement does not exist")
- `/tmp/embercap-pre-phase2-diag.json`                  (pre-Phase-2 diag snapshot)

### Redacted artifacts (committed)

- [phase2/2026-04-25/pmset-custom.txt](./phase2/2026-04-25/pmset-custom.txt)
- [phase2/2026-04-25/pmset-rawlog.txt](./phase2/2026-04-25/pmset-rawlog.txt)
- [phase2/2026-04-25/pmset-assertions.txt](./phase2/2026-04-25/pmset-assertions.txt)
- [phase2/2026-04-25/ioreg-AppleSmartBattery-full.txt](./phase2/2026-04-25/ioreg-AppleSmartBattery-full.txt)
- [phase2/2026-04-25/ioreg-AppleSMC-full.txt](./phase2/2026-04-25/ioreg-AppleSMC-full.txt)
- [phase2/2026-04-25/power-prefs.txt](./phase2/2026-04-25/power-prefs.txt)
- [phase2/2026-04-25/power-prefs.stderr](./phase2/2026-04-25/power-prefs.stderr)
- [phase2/2026-04-25/README.md](./phase2/2026-04-25/README.md)

### Search terms used

Run against each redacted artifact:

- charge-control vocabulary: `charg`, `charging`, `inhibit`, `limit`,
  `optimi[sz]e`, `health`, `target`, `threshold`, `maxcharge`,
  `chargecurrent`, `managed`
- legacy SMC charge keys (Phase 1 carry-over): `BCLM`, `CHLC`, `CHWA`,
  `CH0B`, `CH0C`, `CH0I`, `CH0J`, `CH0K`, `CHBI`
- ioreg writability marker: `(set)` (annotation that flags a property
  as user-settable in `ioreg -l` output; absent ⇒ not advertised as
  writable through the IORegistry)
- ioreg state-only markers: `IsCharging`, `FullyCharged`,
  `ExternalConnected`, `ExternalChargeCapable`, `NotChargingReason`,
  `ChargerData`, `BatteryData.UISoc`, `PostChargeWaitSeconds`,
  `BatteryInvalidWakeSeconds`, `Temperature`, `Voltage`, `Amperage`,
  `InstantAmperage`, `CycleCount`, `CurrentCapacity`, `MaxCapacity`,
  `DesignCapacity`
- userclient discovery: `IOUserClientClass`, `AppleSMCClient`,
  `AppleSmartBatteryManager*`

### Observation summary

- **No `(set)`-annotated property** appears anywhere in either ioreg
  dump (`AppleSmartBattery` subtree or full `AppleSMC` IOService
  subtree). macOS' `ioreg -l` prints `(set)` next to every property
  the IORegistry advertises as user-settable; its complete absence is
  the strongest single signal that no public IORegistry-exposed knob
  controls charging on this Intel `MacBookPro16,1` / macOS 26.4.1
  build.
- **`pmset -g custom`** lists 21 keys per power-domain (Battery / AC).
  Of those, none mention charge, charging, charge limit, charge
  inhibit, optimization, battery health, or any threshold besides the
  unrelated `highstandbythreshold` (a standby-RAM trigger). pmset on
  this build exposes only sleep / wake / lid / display / standby
  policies.
- **`pmset -g assertions`** carries no charge-related assertion. The
  only active assertions are `UserIsActive` (WindowServer keyboard
  tickle), `PreventUserIdleSystemSleep` (sharingd Handoff and a
  user-launched `caffeinate`).
- **`defaults read com.apple.PowerManagement`** reports the domain
  does not exist (stderr: `Domain com.apple.PowerManagement does not
  exist`). No defaults plist underpins charge control on this
  machine.
- **`AppleSmartBattery` ioreg properties** are state-only:
  `IsCharging=No`, `FullyCharged=Yes`, `ExternalConnected=Yes`,
  `ExternalChargeCapable=Yes`, `CurrentCapacity = MaxCapacity = 7467`,
  `DesignCapacity = 8790`, `CycleCount=161`, `Temperature=3066`
  (30.66 °C), `ChargerData = {ChargingCurrent=0, NotChargingReason=4,
  ChargingVoltage=12600, VacVoltageLimit=4210}`,
  `PostChargeWaitSeconds=120`, `PostDischargeWaitSeconds=120`,
  `BatteryInvalidWakeSeconds=30`. None carries `(set)`. The
  `BatteryData` blob exposes raw gauge telemetry (`UISoc`,
  `StateOfCharge`, `Qmax`, `CellVoltage`, `LifetimeData.TimeAtHighSoc`,
  `Flags`); these are likewise read-only.
- **`AppleSmartBatteryManager`** node carries
  `IOUserClientClass = "AppleSmartBatteryManagerUserClient"` (line
  15915 of `ioreg-AppleSMC-full.txt`). The userclient class is
  present, but no public/SIP-permitted property surfaces on the
  manager node itself, and the historical `InflowDisabled`
  charge-inhibit selector that AlDente-style tools targeted is gated
  behind R1 (no SMC/IOKit write attempts) for this charter and was
  not exercised.
- **`AppleSMC`** node carries
  `IOUserClientClass = "AppleSMCClient"` (line 15777). Phase 1 already
  established that on this OS build `IOServiceOpen(AppleSMC)` succeeds
  (`openKr=0`) and `openSession selector=0` succeeds
  (`openSessionKr=0`), but every legacy `getKeyInfo` call against
  charge-relevant keys (`TB0T`, `BNum`, `BSIn`, `BCLM`, `CH0B`,
  `CH0C`, `CHWA`, `CHBI`, `CHLC`) returns `0xe00002c2` /
  `kIOReturnBadArgument`. The Phase 2 ioreg sweep confirms that none
  of those four-character SMC keys is exposed as an IORegistry
  property either — they exist only in SMC firmware, behind an ABI
  this macOS build does not honor.
- **`pmset -g rawlog`** is the most behaviorally informative artifact.
  Across the 03:19–06:31 sample window, the polled lines read
  `AC; Not Charging; 100%; Cap=7467: FCC=7467; Design=8790; ...
  Cycles=161/1000` once per minute. At 06:30:22 the SOC fell to 99%
  (`AC; Not Charging; 99%; Cap=7464: FCC=7473`) without resuming
  charging the next minute (FCC moved 7473→7474 but charge state
  stayed `Not Charging`). This is consistent with a built-in
  hysteresis / re-charge threshold managed by `powerd`/SMC firmware,
  observable as state but not addressable as a tunable from any
  command surveyed.

### Candidate classification

| Source                                    | Key/string                                                                                       | Evidence                                                                                                                                                                            | Classification           | Notes                                                                                                                                                            |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `pmset -g custom`                         | (none)                                                                                           | 21 keys per power domain; zero matches for charge/limit/inhibit/optimi*/target/threshold (charge-related); only sleep/wake/lid/display/standby keys present.                        | no-candidate             | The only `threshold` is `highstandbythreshold = 50` (standby-RAM trigger).                                                                                       |
| `pmset -g rawlog`                         | `AC; Not Charging; 100%`, `AC; Not Charging; 99%`                                                | One-minute-poll output reports state; system stays in `Not Charging` after dropping to 99% on AC (hysteresis). No `pmset` flag toggles this; no setter implied.                     | state-only               | Strongest *behavioral* observation in this phase: the OS already inhibits charging at 100% and rebounds with hysteresis. But pmset rawlog is read-only output.   |
| `pmset -g assertions`                     | (none)                                                                                           | Only sleep-prevention / user-active assertions present; no `Charge*` / `Charging*` / `Inhibit*` assertion namespace listed.                                                         | no-candidate             | —                                                                                                                                                                |
| `defaults read com.apple.PowerManagement` | (domain absent)                                                                                  | stderr: `Domain com.apple.PowerManagement does not exist`                                                                                                                           | no-candidate             | No persisted defaults touch charge policy on this machine.                                                                                                       |
| AppleSmartBattery ioreg                   | `IsCharging`, `FullyCharged`, `ExternalConnected`, `ExternalChargeCapable`, `ChargerData.NotChargingReason=4`, `ChargerData.ChargingCurrent=0`, `BatteryData.UISoc`, `PostChargeWaitSeconds`, `BatteryInvalidWakeSeconds` | All read-only state fields; no `(set)` annotation anywhere in the dump. `NotChargingReason=4` is a state code (the firmware's own *reason*), not a setter.                          | state-only               | Reading these tells us *that* the system is currently not charging on AC and *why*, but exposes no surface to *make* it not charge.                              |
| AppleSmartBatteryManager ioreg            | `IOUserClientClass = AppleSmartBatteryManagerUserClient`                                         | UserClient class is published. No `(set)` properties on the manager node. Historic legacy `InflowDisabled` charge-inhibit selector falls under R1 (no SMC/IOKit write) for this charter and was not exercised. | state-only               | A userclient *exists*, but no advertised write surface and no charter-permitted way to test one.                                                                 |
| AppleSMC ioreg                            | `IOUserClientClass = AppleSMCClient`; no `BCLM/CHLC/CHWA/CH0[BCIJK]/CHBI` ioreg property         | Phase 1 probe already returned `0xe00002c2` / `kIOReturnBadArgument` for all 9 legacy charge keys via the legacy selector-2 `getKeyInfo` path; Phase 2 confirms no fallback ioreg property surface either. | state-only               | The legacy ABI and the IORegistry both refuse to expose these keys on macOS 26.4.1.                                                                              |

### Phase 2 verdict

**`no-candidate`. 0 concrete control candidates identified.**

No public or semi-public control surface on this Intel `MacBookPro16,1` /
macOS 26.4.1 / SIP-enabled build appears to drive charge limiting or
charge inhibition. State surfaces exist (`IsCharging`,
`NotChargingReason`, `pmset -g rawlog` polled state), and the OS itself
clearly already enforces a 100%-with-hysteresis charging policy
internally, but every avenue surveyed in Phase 2 reports state without
exposing a setter.

The Phase 1 SMC-key probe result (uniform `kIOReturnBadArgument` across
all 9 legacy charge keys) and the Phase 2 ioreg / pmset / defaults sweep
are mutually consistent: the documented public macOS charge-control
ABI on Intel pre-Apple-Silicon Macs runs through SMC keys that this
macOS build's user-client no longer accepts, and no replacement public
surface has appeared.

### Gate G2→3

Per charter §5 G2→3, an empty Phase 2 result does **not** abort the
research. Phase 3 (existing-tool evidence: AlDente / bclm / equivalent
on disk, in `/Library/PrivilegedHelperTools`, in `launchctl list`) is
still in scope and is the next step. State explicitly:

> Phase 2 found 0 concrete control candidates; per charter G2→3,
> continue to Phase 3 existing-tool evidence collection. This is not
> yet a negative result by itself.

Phase 4 (mutation) remains gated and **not** authorized: gate H1
(charter §5 G3→4 H1) requires *at least one* concrete control
candidate, which Phase 2 alone has not produced. Phase 4 also remains
forbidden under R1/R3 for any path that would attempt an SMC/IOKit
write or install/start a privileged helper.

### Redaction-pipeline note for this Phase 2 wrap-up

The Phase 2 redactor `scripts/redact-phase2.sh` was extended during
this wrap-up session to cover three additional serial-bearing keys
that surfaced only in the live AppleSMC subtree and were missed by the
initial Phase 2 capture's redacted output:

1. `"SerialNumber"` (single-word, capital S/N) — used by NVMe
   controllers and BCMRAID storage nodes under the AppleSMC IOService
   subtree.
2. `"kUSBSerialNumberString"` — USB descriptor `iSerialNumber` value,
   surfaces under IOUSBHostDevice nodes.
3. `"USB Serial Number"` — IOUSBHostDevice's human-readable mirror of
   the same value.

Three further keys (`iSerialNumber`, `DisplaySerialNumber`,
`FirmwareSerialNumber`) were added defensively for parity with macOS
ioreg conventions even though their values are empty on this machine.

A second mechanical fix was needed: the redactor's `sed` program grew
past BSD `sed`'s practical bracket-balancing limit on a single `-e`
expression once the new keys were appended. The script now writes the
combined program to a temp file (one rule per line) and invokes
`sed -E -f`, which sidesteps the limit. No Phase 1 artifact or
behavior is affected — `scripts/redact-baseline.sh` is unchanged, and
the Phase 1 baseline directory in this commit is byte-identical to
the prior commit.

After the fix, the committed Phase 2 redacted directory was verified
absence-clean for the live battery serial, IOPlatformUUID,
IOPlatformSerialNumber, BatteryData `Serial`, the two USB-bus device
serials (`SerialNumber` / `kUSBSerialNumberString` / `USB Serial
Number` values), the two storage-class serials (`Serial Number` ones),
the `SerialString` USB-C adapter serial, the live username, the live
home path, and the live hostname. No UUID-shape token (regex
`[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}`)
remains anywhere in the redacted directory. Preservation markers
(`CurrentCapacity`, `MaxCapacity`, `DesignCapacity`, `CycleCount`,
`Temperature`, `Voltage`, `Amperage`, `IsCharging`, `FullyCharged`,
`ExternalConnected`, `NotChargingReason`, `AppleSMC`, `lowpowermode`,
`Assertion`) are all present.

### Links

- Charter §3 (safety rules), §4 (redaction), §5 (gates G2→3, G3→4),
  §6 (abort), §7 (artifact conventions)
- Plan "Phase 2 roadmap (next session, not executed now)" — now
  executed in this Phase 2 wrap-up session.

## Phase 3 — existing-tool evidence

> Not executed in this session. See plan "Phase 3 roadmap (next session)" below.

## Phase 4 — 80% mutation test

> Gated. Not authorized until charter G3→4 H1–H5 are all satisfied.
> See plan "Phase 4 roadmap (STUB)" below.

## Phase 5 — report

> Template only; see plan "Phase 5 templates".
