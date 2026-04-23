# embercap — Read-only Battery Diagnostic CLI (Intel Mac / macOS 26)

Status: Draft — awaiting user review
Date: 2026-04-23
Target machine: MacBookPro16,1 (i9-9880H) / macOS 26.4.1 / SIP enabled
Origin prompt: `~/.hermes/workspace/prompts/swift-intel-mac-battery-cli-mvp-intel-direct.md`

## 1. Purpose

embercap is **not** an AlDente-style charge-control tool. It is a **read-only
diagnostic CLI** for this Intel MacBook Pro that:

- reports, with evidence, what battery / charging state the current macOS allows a
  regular user process to observe, and
- demonstrates, with evidence, **why AlDente-style low-level charge control is
  not currently implementable on this OS generation**.

The CLI's purpose is deliberately reframed from "control charging" to
"explain, on this machine, why we cannot control charging the old way." The
README and `--help` output must state this plainly.

## 2. Evidence (Intel machine reconnaissance — 2026-04-23)

Verified directly on the target machine before this spec was written.

Host / toolchain
- Model: MacBookPro16,1, 8-core Intel Core i9-9880H, 32 GB
- Kernel: Darwin 25.4.0 x86_64 (macOS 26.4.1, BuildVersion 25E253)
- SIP: enabled
- Xcode: none installed; Xcode Command Line Tools at `/Library/Developer/CommandLineTools`
- Swift: 6.3.1, SwiftPM available, target `x86_64-apple-macosx26.0`

Public battery APIs (no privileges)
- `IOPSCopyPowerSourcesInfo` / `IOPSCopyPowerSourcesList`: returns the internal
  battery with `Current Capacity`, `Max Capacity`, `Is Charging`, `Is Present`,
  `Power Source State`, `Hardware Serial Number`, and time estimates.
- `ioreg -rn AppleSmartBattery`: exposes `CycleCount`, `Temperature`,
  `DesignCapacity`, `ChargerData.NotChargingReason`, `BatteryData.StateOfCharge`,
  and more.
- `pmset -g batt`: works; gives a single-line summary.

AppleSMC userland ABI — the critical finding
- `IOServiceGetMatchingService("AppleSMC")` matches; the `AppleSMC` node in the
  IORegistry advertises `IOUserClientClass = "AppleSMCClient"`.
- At test time, **6 live `AppleSMCClient` instances** are already attached to
  `AppleSMC` (owned by system daemons), proving the driver and its user-client
  are fully alive on this OS.
- `IOServiceOpen(AppleSMC, …)` from our unsigned Swift CLI: **succeeds**
  (`io_connect_t` returned).
- `IOConnectCallScalarMethod(selector=0)` on that connection — the legacy
  "open session" entry point: returns `kIOReturnSuccess`.
- `IOConnectCallStructMethod(selector=2, data8=9 getKeyInfo)` with the canonical
  76-byte `SMCKeyData_t` (the protocol used by `zackelia/bclm`, `beltex/SMCKit`,
  `iStats`, etc.): **returns `kIOReturnBadArgument` (`0xe00002c2`) for every key
  tried**, including sanity keys that must exist on any Intel Mac firmware:
  - `TB0T` (battery temperature) — fails
  - `BNum` (battery count), `BSIn` (battery instant) — fail
  - legacy charge-control keys `BCLM`, `CH0B`, `CH0C`, `CHWA`, `CHBI`, `CHLC` —
    all fail identically
- Struct-size variants of 76 / 80 / 96 bytes all produce the same
  `kIOReturnBadArgument`, ruling out a simple layout mismatch.

Interpretation
- The driver and user-client are alive and being driven by Apple's own daemons,
  so access itself is not the block.
- The **legacy `selector=2` + `SMCKeyData_t` read ABI** — the foundation of
  bclm / AlDente / SMCKit / iStats — **is rejected at the driver on macOS 26**.
- This is consistent with, and more extensive than, bclm's own README note that
  bclm stopped working on macOS ≥ 15: the write path is not "blocked," the
  whole legacy read path is gone.
- Because the legacy read path is dead, the legacy write path (`BCLM`, `CH0B`,
  `CHWA`) cannot even be reached through the same protocol.

## 3. Why `enable` / `disable` / `target` are not implemented

Three independent reasons, each sufficient alone:

1. **Direct evidence.** Probe returns `kIOReturnBadArgument` for every read in
   the legacy ABI on this machine. Writes cannot succeed where reads are
   rejected at the same call site.
2. **Upstream precedent.** `zackelia/bclm#49` and the project's own README
   document that the protocol has been broken since macOS 15; we are on
   macOS 26, two Darwin major versions further along, with stricter kext
   policy.
3. **Maintenance risk, even on success.** System daemons clearly use *some*
   modern dispatch, but it is private and unstable across OS point releases.
   Personal-use software on a machine that receives regular OS updates cannot
   depend on a reverse-engineered, undocumented selector without accepting
   frequent breakage and potential power-state misbehaviour.

Shipping stub `enable` / `disable` / `target` commands that silently no-op or
fail opaquely would be dishonest and would defeat the purpose of the tool.

## 4. Research-branch carve-out

Reverse-engineering the modern `AppleSMCClient` dispatch (e.g. via
`class-dump` / symbol tracing on `powerd`, `coreduetd`; or comparing against
VirtualSMC) is **explicitly scoped out of `main`**. Any such exploration lives
in a separate `research/` directory or branch, is not built by default, and
does not enter `main` unless the discovered write path:

- is stable across at least two macOS point releases, and
- can be driven from a code-signed binary without an entitlement the user
  cannot obtain, and
- degrades safely when the path disappears on a future macOS update.

## 5. CLI surface (all commands read-only)

```
embercap status          Human-readable battery / charging summary
embercap probe           Structured feasibility probe of AppleSMC legacy ABI
embercap diag [--format=json|markdown]
                         Machine-readable report (default: json)
embercap version         Build + machine fingerprint
embercap help            Usage
```

### 5.1 `status`
Sources: `IOPSCopyPowerSourcesInfo` (primary) + selected
`AppleSmartBattery` IORegistry properties (read via `IORegistryEntryCreate…`,
not by shelling out). Reports:
- Model, serial, cycle count
- Design capacity, max capacity, current capacity, charge %
- Is charging, external power connected, adapter info
- Temperature (°C, from `AppleSmartBattery.Temperature / 100`)
- `NotChargingReason` decoded (when not charging)
- Time-to-full or time-to-empty when available

### 5.2 `probe`
Labeled, ordered steps; each step prints outcome and raw `kern_return_t` in hex
with `mach_error_string`.

1. Match `AppleSMC` service.
2. `IOServiceOpen` → `AppleSMCClient`.
3. `IOConnectCallScalarMethod(selector=0)` — openSession.
4. `IOConnectCallStructMethod(selector=2, data8=kSMCGetKeyInfo=9)` on the
   following keys, with the canonical 76-byte `SMCKeyData_t`:
   - `TB0T`, `BNum`, `BSIn` (sanity keys)
   - `BCLM`, `CH0B`, `CH0C`, `CHWA`, `CHBI`, `CHLC` (legacy charge-control keys)
5. Summarize verdict:
   - if all step-4 calls fail with `kIOReturnBadArgument`, classify as
     **"legacy SMC ABI unavailable — consistent with bclm broken on macOS ≥ 15"**
   - if some step-4 calls succeed, report raw data and flag as unexpected
     (prompt for research-branch follow-up)

Exit code semantics:
- `0` — probe completed and produced a verdict (even if the verdict is
  "legacy ABI unavailable")
- non-zero — the probe itself failed to run (e.g. `IOServiceOpen` returned
  an unexpected error)

### 5.3 `diag`
Aggregates:
- Machine fingerprint (model, CPU, macOS version + build, SIP state, kernel)
- Toolchain fingerprint (Swift version, SDK, embercap version + commit SHA)
- Public-API battery snapshot (same fields as `status`)
- Raw probe results (per-step `kern_return_t` hex, sub-class decode, per-key
  outcomes)

Serialization: JSON (stable schema documented in `docs/diag-schema.md`) or
Markdown. Schema includes a top-level `schemaVersion` field.

### 5.4 `version`
- `embercap` version string, commit SHA, build date
- Machine fingerprint one-liner

## 6. Architecture

Single SwiftPM executable target `embercap` (already exists). No external
dependencies — IOKit system framework only. Deployment target: macOS 12.

Files (one responsibility each):
- `embercap.swift` — `@main`, argv dispatch, usage
- `MachineInfo.swift` — `sysctlbyname`, `sw_vers`, SIP state, build SHA
- `BatteryStatus.swift` — `IOPSCopy*` wrapper + selected `AppleSmartBattery`
  IORegistry property reader
- `SMC.swift` — thin IOKit wrapper: match, open, openSession, struct-method
  call, `SMCKeyData_t` layout, `kern_return_t` formatting
- `ProbeSMC.swift` — ordered, labeled probe steps, verdict classifier
- `Diag.swift` — aggregate model + JSON / Markdown serializer
- `Output.swift` — printing helpers (table rows, padding, byte hex)

Language mode: Swift 6 strict concurrency. Everything is single-threaded
synchronous; no async needed.

## 7. Error handling

- Every IOKit call's `kern_return_t` is carried through and printed as
  `"<mach_error_string> (0x%08x)"`. No return value is silently discarded.
- `probe` never exits non-zero solely because the legacy ABI rejected a call
  — that is the expected observation on this machine and is the whole point of
  the tool.
- `status` tolerates missing individual properties (e.g. `Temperature` absent
  on some power states); prints "n/a" rather than aborting.
- No `try!`, no force-unwraps on external data. All failures produce a visible
  one-line explanation.

## 8. Testing

- Unit tests (Swift Testing, fast, CI-suitable):
  - `fourCC` round-trip with known keys
  - `kern_return_t` formatter prints expected hex for known codes
  - `Diag` JSON encoder produces stable top-level schema
  - probe verdict classifier: given canned step results, returns the correct
    verdict string
- Integration tests (only meaningful on the target machine):
  - `status` produces non-empty output including `Current Capacity`
  - `probe` exits 0 and, on this machine today, reports the "legacy SMC ABI
    unavailable" verdict; captured as a reference transcript under
    `docs/samples/probe-macos26-mbp161.txt`
- Regression sample: `docs/samples/diag-macos26-mbp161.json` committed so
  future OS upgrades can be compared against a known baseline.

## 9. README framing

README order (enforced):
1. "embercap is not a charge-control tool."
2. "It is a read-only diagnostic CLI that explains *why* AlDente-style charge
   control is not currently implementable on this Intel Mac / this macOS."
3. One-page evidence summary (machine, probe outcomes, error codes) — this
   spec's §2 condensed.
4. Usage for `status`, `probe`, `diag`, `version`.
5. Short "research notes" section pointing at the research-branch carve-out
   (§4) and noting that any future write-path work is out of scope for `main`.

## 10. Out of scope (explicit)

- `enable`, `disable`, `target`, `daemon` commands.
- Any reverse-engineering of the modern `AppleSMCClient` dispatch inside
  `main`. (Allowed only in a separate research branch per §4.)
- Apple Silicon support. Scope is this Intel target machine.
- Cross-platform abstractions.
- Homebrew formula, notarization, code signing. The tool is built locally
  with `swift build` for personal use.

## 11. Acceptance criteria

An implementation of this spec is complete when:
1. `swift build` succeeds on the target machine with Xcode CLT only.
2. `embercap status` prints a populated battery summary.
3. `embercap probe` exits 0 and reports the "legacy SMC ABI unavailable"
   verdict with per-step evidence on the target machine.
4. `embercap diag --format=json` emits a document matching the schema,
   including machine fingerprint and probe evidence.
5. `embercap diag --format=markdown` emits the same information as a
   human-readable report.
6. README matches §9.
7. Sample probe + diag transcripts for this machine are committed under
   `docs/samples/`.
8. No command touches a write code path. A grep for `writeKey` /
   `kSMCWriteKey` / selector-6 usages in `Sources/` returns zero matches in
   the shipped `main` branch.
