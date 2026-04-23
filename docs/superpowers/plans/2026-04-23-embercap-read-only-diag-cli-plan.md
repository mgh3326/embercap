# embercap Read-only Diagnostic CLI — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a read-only Swift CLI for this Intel MacBookPro16,1 running macOS 26.4.1 that exposes battery state via public APIs and reports, with evidence, why the legacy AlDente / bclm SMC write path is no longer reachable on this OS.

**Architecture:** Single SwiftPM executable (`embercap`) composed of small single-purpose modules. All user-facing commands are read-only. Pure logic (verdict classifier, `fourCC`, formatters, `Codable` encoders) is unit-tested with Swift Testing. Hardware-touching code has integration tests that run on the target machine. No third-party dependencies; IOKit system framework only.

**Tech Stack:** Swift 6.3.1 (tools-version 6.3, `.v6` language mode), SwiftPM, IOKit, Swift Testing, Xcode Command Line Tools. Deployment target: macOS 12.

**Spec:** [docs/superpowers/specs/2026-04-23-embercap-read-only-diag-cli-design.md](../specs/2026-04-23-embercap-read-only-diag-cli-design.md)

---

## File structure (decomposition locked in here)

Sources — one responsibility per file:

| File | Responsibility |
| --- | --- |
| `Sources/embercap/embercap.swift` | `@main`, argv dispatch, usage text, exit codes |
| `Sources/embercap/Output.swift` | pure helpers: `pad`, `hexByte`, `fourCC`↔string, `machErrorString` |
| `Sources/embercap/SMC.swift` | `SMCKeyData_t` layout, `SMC.open`, `openSession`, `call` |
| `Sources/embercap/ProbeSMC.swift` | probe runner + pure `Verdict` classifier |
| `Sources/embercap/MachineInfo.swift` | `sysctlbyname`, `sw_vers`, SIP state, kernel string |
| `Sources/embercap/BatteryStatus.swift` | `IOPSCopy*` + `AppleSmartBattery` IORegistry snapshot |
| `Sources/embercap/Diag.swift` | `Codable` aggregate + JSON + Markdown renderers |
| `Sources/embercap/Version.swift` | build-time version string + runtime commit SHA lookup |

Tests:

| File | What it pins down |
| --- | --- |
| `Tests/embercapTests/OutputTests.swift` | `fourCC` round-trip, `pad`, `hexByte`, `machErrorString` shape |
| `Tests/embercapTests/SMCLayoutTests.swift` | `MemoryLayout<SMCKeyData_t>.size == 76`, field offsets |
| `Tests/embercapTests/ProbeClassifierTests.swift` | verdict classifier covers all four branches |
| `Tests/embercapTests/MachineInfoTests.swift` | SIP parser: `enabled` / `disabled` / unknown |
| `Tests/embercapTests/DiagEncoderTests.swift` | `Diag` JSON schema top-level keys, Markdown sections |
| `Tests/embercapTests/IntegrationProbeTests.swift` | on-host: `probe` exits 0 and emits `legacy-abi-unavailable` |

Docs & samples:

| File | What it is |
| --- | --- |
| `README.md` | Order enforced per spec §9 |
| `docs/diag-schema.md` | JSON schema for `diag --format=json` |
| `docs/samples/probe-macos26-mbp161.txt` | Captured `probe` output on the target host |
| `docs/samples/diag-macos26-mbp161.json` | Captured `diag --format=json` output |
| `docs/samples/diag-macos26-mbp161.md` | Captured `diag --format=markdown` output |

---

## Conventions

- Swift Testing only (no XCTest). Every test file starts with `import Testing` and `@testable import embercap`.
- Commits after every task. Commit messages use Conventional Commits (`feat:`, `test:`, `docs:`, `refactor:`, `chore:`).
- No external dependencies beyond the macOS SDK.
- No `try!`, no force-unwraps. All IOKit return codes are formatted via `machErrorString`.
- Every hardware-touching run command is annotated "run on the target machine."

---

## Task 1 — Baseline: reset Sources/Tests to a clean slate matching the spec

**Why:** The current `Sources/embercap/` has evidence-gathering probe code that was useful for the feasibility probe but whose shape (no tests, debug `LayoutCheck`, `%s`-unsafe printers already removed, file responsibilities not yet matching spec) is not what we want to keep. Start clean so every subsequent task follows the spec decomposition.

**Files:**
- Delete (untracked, never committed): `Sources/embercap/BatteryStatus.swift`, `Sources/embercap/LayoutCheck.swift`, `Sources/embercap/ProbeSMC.swift`, `Sources/embercap/SMC.swift`
- Replace: `Sources/embercap/embercap.swift` — minimal stub that prints a usage banner
- Replace: `Tests/embercapTests/embercapTests.swift` — minimal smoke test that proves `swift test` runs
- Confirm unchanged: `Package.swift` (already has `.macOS(.v12)` and `.v6` language mode)

- [ ] **Step 1.1: Delete probe artifacts**

Run:
```bash
cd /Users/mgh3326/swift-projects/embercap
rm -f Sources/embercap/BatteryStatus.swift Sources/embercap/LayoutCheck.swift Sources/embercap/ProbeSMC.swift Sources/embercap/SMC.swift
ls Sources/embercap/
```
Expected: only `embercap.swift` remains.

- [ ] **Step 1.2: Replace `Sources/embercap/embercap.swift` with a minimal stub**

Overwrite `Sources/embercap/embercap.swift` with exactly:

```swift
import Foundation

@main
struct Embercap {
    static let usage = """
    embercap — read-only battery diagnostic CLI for Intel Mac / macOS 26
    Usage:
      embercap status          Human-readable battery summary
      embercap probe           Feasibility probe of AppleSMC legacy ABI
      embercap diag [--format=json|markdown]
                               Machine-readable diagnostic report
      embercap version         Build + machine fingerprint
      embercap help            This message
    """

    static func main() {
        setlinebuf(stdout)
        let args = Array(CommandLine.arguments.dropFirst())
        guard let cmd = args.first else {
            print(usage)
            return
        }
        switch cmd {
        case "help", "-h", "--help":
            print(usage)
        default:
            FileHandle.standardError.write(Data("unknown command: \(cmd)\n".utf8))
            print(usage)
            exit(64) // EX_USAGE
        }
    }
}
```

- [ ] **Step 1.3: Replace `Tests/embercapTests/embercapTests.swift` with a smoke test**

Overwrite `Tests/embercapTests/embercapTests.swift` with exactly:

```swift
import Testing
@testable import embercap

@Test func usageBannerMentionsAllCommands() {
    let banner = Embercap.usage
    #expect(banner.contains("status"))
    #expect(banner.contains("probe"))
    #expect(banner.contains("diag"))
    #expect(banner.contains("version"))
    #expect(banner.contains("help"))
}
```

- [ ] **Step 1.4: Build and test**

Run on the target machine:
```bash
swift build
swift test
```
Expected: both succeed. Test reports 1 passing.

- [ ] **Step 1.5: Commit the baseline**

```bash
git add Sources/embercap/embercap.swift Tests/embercapTests/embercapTests.swift Package.swift .gitignore
git -c commit.gpgsign=false commit -m "chore: baseline clean Sources and Tests matching spec decomposition

Drop probe artifacts used for Phase 2 evidence gathering; they served their
purpose (see spec §2) and will be rebuilt module-by-module with tests in
the following tasks."
```

Verify:
```bash
git log --oneline
```
Expected: three commits total (two docs + this baseline).

---

## Task 2 — `Output` module with pure-function tests

**Why:** Small helpers used by every other module. Pure logic, easy to lock down with unit tests first.

**Files:**
- Create: `Sources/embercap/Output.swift`
- Create: `Tests/embercapTests/OutputTests.swift`

- [ ] **Step 2.1: Write failing tests for `Output`**

Create `Tests/embercapTests/OutputTests.swift`:

```swift
import Testing
import Foundation
@testable import embercap

@Test func fourCCPacksBigEndian() {
    #expect(fourCC("BCLM") == 0x42434C4D)
    #expect(fourCC("TB0T") == 0x5442_3054)
    #expect(fourCC("CH0B") == 0x4348_3042)
}

@Test func fourCCToStringIsInverse() {
    for key in ["BCLM", "TB0T", "CH0B", "BNum"] {
        #expect(fourCCToString(fourCC(key)) == key)
    }
}

@Test func padPadsOnRight() {
    #expect(pad("abc", 6) == "abc   ")
    #expect(pad("abcdef", 4) == "abcd")   // truncates
    #expect(pad("", 3) == "   ")
}

@Test func hexByteIsTwoCharsLowercase() {
    #expect(hexByte(0) == "00")
    #expect(hexByte(0xff) == "ff")
    #expect(hexByte(0x0a) == "0a")
}

@Test func machErrorStringContainsHex() {
    // kIOReturnSuccess == 0; function should produce something like
    // "(success) (0x00000000)". Exact label wording is provided by the
    // system, but hex must appear.
    let s = machErrorString(0)
    #expect(s.contains("0x00000000"))
}
```

- [ ] **Step 2.2: Run the test to verify it fails**

```bash
swift test --filter OutputTests
```
Expected: compile error (`cannot find 'fourCC' in scope`), or failure. Either way, pre-implementation.

- [ ] **Step 2.3: Implement `Output.swift`**

Create `Sources/embercap/Output.swift`:

```swift
import Foundation
import Darwin

func fourCC(_ s: String) -> UInt32 {
    precondition(s.utf8.count == 4, "SMC key must be exactly 4 ASCII chars: \(s)")
    let b = Array(s.utf8)
    return (UInt32(b[0]) << 24) | (UInt32(b[1]) << 16) | (UInt32(b[2]) << 8) | UInt32(b[3])
}

func fourCCToString(_ code: UInt32) -> String {
    let bytes: [UInt8] = [
        UInt8((code >> 24) & 0xff),
        UInt8((code >> 16) & 0xff),
        UInt8((code >> 8) & 0xff),
        UInt8(code & 0xff),
    ]
    return String(bytes: bytes, encoding: .ascii) ?? "????"
}

func pad(_ s: String, _ width: Int) -> String {
    if s.count >= width { return String(s.prefix(width)) }
    return s + String(repeating: " ", count: width - s.count)
}

func hexByte(_ b: UInt8) -> String {
    return String(format: "%02x", b)
}

func machErrorString(_ kr: Int32) -> String {
    let raw = mach_error_string(kr).map { String(cString: $0) } ?? "unknown"
    let hex = String(format: "0x%08x", UInt32(bitPattern: kr))
    return "\(raw) (\(hex))"
}
```

- [ ] **Step 2.4: Run the tests to verify they pass**

```bash
swift test --filter OutputTests
```
Expected: 5 tests passing.

- [ ] **Step 2.5: Commit**

```bash
git add Sources/embercap/Output.swift Tests/embercapTests/OutputTests.swift
git -c commit.gpgsign=false commit -m "feat(output): fourCC, pad, hexByte, machErrorString with tests"
```

---

## Task 3 — `SMC` core: layout, open, call

**Why:** Wraps the IOKit surface the probe needs. Layout is verified by unit test so any Swift/C-layout drift is caught immediately. Hardware open/call is exercised indirectly via Task 5's integration test.

**Files:**
- Create: `Sources/embercap/SMC.swift`
- Create: `Tests/embercapTests/SMCLayoutTests.swift`

- [ ] **Step 3.1: Write failing layout tests**

Create `Tests/embercapTests/SMCLayoutTests.swift`:

```swift
import Testing
@testable import embercap

@Test func smcKeyDataTotalSizeMatchesCLayout() {
    #expect(MemoryLayout<SMCKeyData_t>.size == 76)
}

@Test func smcKeyDataFieldOffsetsMatchCLayout() {
    #expect(MemoryLayout<SMCKeyData_t>.offset(of: \.key) == 0)
    #expect(MemoryLayout<SMCKeyData_t>.offset(of: \.vers) == 4)
    #expect(MemoryLayout<SMCKeyData_t>.offset(of: \.pLimitData) == 12)
    #expect(MemoryLayout<SMCKeyData_t>.offset(of: \.keyInfo) == 28)
    #expect(MemoryLayout<SMCKeyData_t>.offset(of: \.result) == 37)
    #expect(MemoryLayout<SMCKeyData_t>.offset(of: \.status) == 38)
    #expect(MemoryLayout<SMCKeyData_t>.offset(of: \.data8) == 39)
    #expect(MemoryLayout<SMCKeyData_t>.offset(of: \.data32) == 40)
}
```

- [ ] **Step 3.2: Run tests and verify they fail to compile**

```bash
swift test --filter SMCLayoutTests
```
Expected: compile failure (`cannot find 'SMCKeyData_t' in scope`).

- [ ] **Step 3.3: Implement `SMC.swift`**

Create `Sources/embercap/SMC.swift`:

```swift
import Foundation
import IOKit

struct SMCKeyData_vers_t {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

struct SMCKeyData_pLimitData_t {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

struct SMCKeyData_keyInfo_t {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

struct SMCKeyData_t {
    var key: UInt32 = 0
    var vers = SMCKeyData_vers_t()
    var pLimitData = SMCKeyData_pLimitData_t()
    var keyInfo = SMCKeyData_keyInfo_t()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    ) = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}

enum SMCSubCommand: UInt8 {
    case getKeyInfo = 9
    case readKey = 5
}

// kSMCHandleYPCEvent: the legacy dispatch selector used by bclm / SMCKit /
// iStats to drive structured key access. On macOS >= 15 this path has been
// observed to return kIOReturnBadArgument for every key. See spec §2 for the
// Intel-machine evidence.
let kSMCUserClientSelector: UInt32 = 2

struct SMCError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

struct SMC {
    let conn: io_connect_t

    static func open() -> Result<SMC, SMCError> {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        if service == 0 {
            return .failure(SMCError(message: "IOServiceGetMatchingService(\"AppleSMC\") returned 0"))
        }
        var conn: io_connect_t = 0
        let kr = IOServiceOpen(service, mach_task_self_, 0, &conn)
        IOObjectRelease(service)
        if kr != kIOReturnSuccess {
            return .failure(SMCError(message: "IOServiceOpen failed: \(machErrorString(kr))"))
        }
        return .success(SMC(conn: conn))
    }

    func close() {
        IOServiceClose(conn)
    }

    /// Calls the legacy `kSMCHandleYPCEvent` (selector 2) struct-method entry point.
    func call(_ input: inout SMCKeyData_t) -> (kern_return_t, SMCKeyData_t) {
        var output = SMCKeyData_t()
        let size = MemoryLayout<SMCKeyData_t>.size
        var outSize = size
        let kr = withUnsafePointer(to: &input) { inPtr in
            withUnsafeMutablePointer(to: &output) { outPtr in
                IOConnectCallStructMethod(conn, kSMCUserClientSelector, inPtr, size, outPtr, &outSize)
            }
        }
        return (kr, output)
    }

    /// Calls the legacy `openSession` entry point (selector 0, scalar, no args).
    /// Some AppleSMCClient builds require this before struct calls; on modern
    /// macOS it still returns success but the struct call that follows does
    /// not (see spec §2).
    func openSession() -> kern_return_t {
        return IOConnectCallScalarMethod(conn, 0, nil, 0, nil, nil)
    }
}
```

- [ ] **Step 3.4: Run the layout tests and verify they pass**

```bash
swift test --filter SMCLayoutTests
```
Expected: 2 tests passing. Hint: if any offset fails, Swift's layout has drifted from C — do not patch the expected numbers; fix the struct.

- [ ] **Step 3.5: Commit**

```bash
git add Sources/embercap/SMC.swift Tests/embercapTests/SMCLayoutTests.swift
git -c commit.gpgsign=false commit -m "feat(smc): SMCKeyData_t layout, open/openSession/call with layout tests"
```

---

## Task 4 — Probe verdict classifier (pure)

**Why:** This is the one piece of probe logic that has no hardware dependency and can be fully unit-tested. Isolating it keeps the on-host probe runner simple.

**Files:**
- Create: `Sources/embercap/ProbeSMC.swift` (classifier half only in this task)
- Create: `Tests/embercapTests/ProbeClassifierTests.swift`

- [ ] **Step 4.1: Write failing classifier tests**

Create `Tests/embercapTests/ProbeClassifierTests.swift`:

```swift
import Testing
import IOKit
@testable import embercap

@Test func allBadArgumentYieldsLegacyAbiUnavailable() {
    let results: [ProbeKeyResult] = [
        .init(key: "TB0T", infoKr: kIOReturnBadArgument, readKr: nil),
        .init(key: "BCLM", infoKr: kIOReturnBadArgument, readKr: nil),
        .init(key: "CH0B", infoKr: kIOReturnBadArgument, readKr: nil),
    ]
    #expect(classifyProbe(results) == .legacyAbiUnavailable)
}

@Test func anyNotPrivilegedYieldsBlockedByPolicy() {
    let results: [ProbeKeyResult] = [
        .init(key: "TB0T", infoKr: kIOReturnBadArgument, readKr: nil),
        .init(key: "BCLM", infoKr: kIOReturnNotPrivileged, readKr: nil),
    ]
    #expect(classifyProbe(results) == .blockedByPolicy)
}

@Test func anyNotPermittedYieldsBlockedByPolicy() {
    let results: [ProbeKeyResult] = [
        .init(key: "BCLM", infoKr: kIOReturnNotPermitted, readKr: nil),
    ]
    #expect(classifyProbe(results) == .blockedByPolicy)
}

@Test func anySuccessYieldsPartialSuccess() {
    let results: [ProbeKeyResult] = [
        .init(key: "TB0T", infoKr: kIOReturnSuccess, readKr: kIOReturnSuccess),
        .init(key: "BCLM", infoKr: kIOReturnBadArgument, readKr: nil),
    ]
    #expect(classifyProbe(results) == .partialSuccess)
}

@Test func otherMixedErrorsYieldInconclusive() {
    let results: [ProbeKeyResult] = [
        .init(key: "TB0T", infoKr: kIOReturnBadArgument, readKr: nil),
        .init(key: "CHWA", infoKr: kIOReturnNotFound, readKr: nil),
    ]
    #expect(classifyProbe(results) == .inconclusive)
}
```

- [ ] **Step 4.2: Run the tests and verify they fail**

```bash
swift test --filter ProbeClassifierTests
```
Expected: compile failure (`cannot find 'ProbeKeyResult'`).

- [ ] **Step 4.3: Implement the classifier half of `ProbeSMC.swift`**

Create `Sources/embercap/ProbeSMC.swift`:

```swift
import Foundation
import IOKit

struct ProbeKeyResult: Sendable, Equatable {
    let key: String
    let infoKr: kern_return_t
    let readKr: kern_return_t?  // nil if getKeyInfo failed so readKey was skipped
}

enum ProbeVerdict: String, Sendable, Equatable {
    case legacyAbiUnavailable = "legacy-abi-unavailable"
    case blockedByPolicy      = "blocked-by-policy"
    case partialSuccess       = "partial-success"
    case inconclusive         = "inconclusive"
}

func classifyProbe(_ results: [ProbeKeyResult]) -> ProbeVerdict {
    if results.isEmpty { return .inconclusive }

    if results.contains(where: { $0.infoKr == kIOReturnSuccess }) {
        return .partialSuccess
    }

    let policyCodes: Set<kern_return_t> = [kIOReturnNotPrivileged, kIOReturnNotPermitted]
    if results.contains(where: { policyCodes.contains($0.infoKr) }) {
        return .blockedByPolicy
    }

    if results.allSatisfy({ $0.infoKr == kIOReturnBadArgument }) {
        return .legacyAbiUnavailable
    }

    return .inconclusive
}
```

- [ ] **Step 4.4: Run the tests and verify they pass**

```bash
swift test --filter ProbeClassifierTests
```
Expected: 5 tests passing.

- [ ] **Step 4.5: Commit**

```bash
git add Sources/embercap/ProbeSMC.swift Tests/embercapTests/ProbeClassifierTests.swift
git -c commit.gpgsign=false commit -m "feat(probe): pure verdict classifier with four-branch coverage tests"
```

---

## Task 5 — Probe runner (hardware) + integration test

**Why:** Combines the classifier with on-host SMC calls to produce the actual labeled probe steps. Verified against this Intel machine.

**Files:**
- Modify: `Sources/embercap/ProbeSMC.swift`
- Create: `Tests/embercapTests/IntegrationProbeTests.swift`

- [ ] **Step 5.1: Add the probe runner to `ProbeSMC.swift`**

Append to `Sources/embercap/ProbeSMC.swift`:

```swift
struct ProbeReport: Sendable, Equatable {
    /// Did `IOServiceGetMatchingService("AppleSMC")` find a service?
    let matchedService: Bool
    /// Did `IOServiceOpen` succeed?
    let openKr: kern_return_t?
    /// Did `IOConnectCallScalarMethod(selector=0)` (openSession) succeed?
    let openSessionKr: kern_return_t?
    /// Per-key getKeyInfo/readKey outcomes.
    let keyResults: [ProbeKeyResult]
    /// Classifier verdict.
    let verdict: ProbeVerdict
}

enum ProbeRunner {
    // Sanity keys (expected-present on any Intel Mac firmware) + the legacy
    // charge-control keys we want to know the fate of.
    static let probeKeys: [String] = [
        "TB0T", "BNum", "BSIn",
        "BCLM", "CH0B", "CH0C", "CHWA", "CHBI", "CHLC",
    ]

    static func run() -> ProbeReport {
        switch SMC.open() {
        case .failure:
            return ProbeReport(
                matchedService: false,
                openKr: nil,
                openSessionKr: nil,
                keyResults: [],
                verdict: .inconclusive
            )
        case .success(let smc):
            defer { smc.close() }
            let sess = smc.openSession()
            var results: [ProbeKeyResult] = []
            for key in probeKeys {
                results.append(readOne(smc, key: key))
            }
            return ProbeReport(
                matchedService: true,
                openKr: kIOReturnSuccess,
                openSessionKr: sess,
                keyResults: results,
                verdict: classifyProbe(results)
            )
        }
    }

    private static func readOne(_ smc: SMC, key: String) -> ProbeKeyResult {
        var req = SMCKeyData_t()
        req.key = fourCC(key)
        req.data8 = SMCSubCommand.getKeyInfo.rawValue
        let (infoKr, info) = smc.call(&req)
        if infoKr != kIOReturnSuccess {
            return ProbeKeyResult(key: key, infoKr: infoKr, readKr: nil)
        }
        var req2 = SMCKeyData_t()
        req2.key = fourCC(key)
        req2.keyInfo.dataSize = info.keyInfo.dataSize
        req2.data8 = SMCSubCommand.readKey.rawValue
        let (readKr, _) = smc.call(&req2)
        return ProbeKeyResult(key: key, infoKr: infoKr, readKr: readKr)
    }
}

func renderProbeHuman(_ r: ProbeReport) -> String {
    var out = "== embercap SMC probe (read-only) ==\n\n"
    out += "[1] match AppleSMC:          \(r.matchedService ? "ok" : "FAIL")\n"
    if let k = r.openKr { out += "[2] IOServiceOpen:           \(machErrorString(k))\n" }
    if let k = r.openSessionKr { out += "[3] openSession (sel 0):     \(machErrorString(k))\n" }
    out += "\n[4] legacy selector-2 key access (no writes):\n"
    out += "    key    info                                 read\n"
    for kr in r.keyResults {
        let infoCol = pad(machErrorString(kr.infoKr), 36)
        let readCol = kr.readKr.map { machErrorString($0) } ?? "(skipped)"
        out += "    \(pad(kr.key, 6)) \(infoCol) \(readCol)\n"
    }
    out += "\nverdict: \(r.verdict.rawValue)\n"
    switch r.verdict {
    case .legacyAbiUnavailable:
        out += "  Legacy bclm/SMCKit ABI is rejected at the driver on this OS.\n"
        out += "  Consistent with bclm broken on macOS >= 15 (see spec §2).\n"
    case .blockedByPolicy:
        out += "  Access was refused with a privilege error. The tool does not\n"
        out += "  attempt to escalate; the raw error is printed above.\n"
    case .partialSuccess:
        out += "  At least one key responded with kIOReturnSuccess. This is\n"
        out += "  unexpected on macOS 26 and may warrant the research branch.\n"
    case .inconclusive:
        out += "  Mixed errors. Raw per-key return codes above.\n"
    }
    return out
}
```

- [ ] **Step 5.2: Write the hardware integration test**

Create `Tests/embercapTests/IntegrationProbeTests.swift`:

```swift
import Testing
@testable import embercap

@Test(.tags(.hardware))
func probeOnThisIntelMacReportsLegacyAbiUnavailable() {
    let r = ProbeRunner.run()
    #expect(r.matchedService == true)
    #expect(r.openKr == kIOReturnSuccess)
    // On this machine today we expect the legacy path to be rejected.
    // If this assertion flips on a future macOS, that is a genuine signal
    // worth investigating (see spec §4 research-branch carve-out).
    #expect(r.verdict == .legacyAbiUnavailable)
    #expect(r.keyResults.count == ProbeRunner.probeKeys.count)
}

extension Tag {
    @Tag static var hardware: Self
}
```

- [ ] **Step 5.3: Run the full test suite on the target machine**

```bash
swift test
```
Expected: all tests pass (unit + layout + classifier + integration). The integration test requires this Intel machine on the current macOS; on any other host the `verdict` assertion may not hold.

- [ ] **Step 5.4: Commit**

```bash
git add Sources/embercap/ProbeSMC.swift Tests/embercapTests/IntegrationProbeTests.swift
git -c commit.gpgsign=false commit -m "feat(probe): on-host runner and human renderer with integration test"
```

---

## Task 6 — `MachineInfo` module

**Why:** Diag and version need a consistent machine fingerprint. Parsing `sw_vers` output and `csrutil status` via `Process` is pure once the raw strings are in hand, so the parsers are unit-testable.

**Files:**
- Create: `Sources/embercap/MachineInfo.swift`
- Create: `Tests/embercapTests/MachineInfoTests.swift`

- [ ] **Step 6.1: Write failing parser tests**

Create `Tests/embercapTests/MachineInfoTests.swift`:

```swift
import Testing
@testable import embercap

@Test func parseSIPEnabled() {
    #expect(parseSIPStatus("System Integrity Protection status: enabled.") == .enabled)
}

@Test func parseSIPDisabled() {
    #expect(parseSIPStatus("System Integrity Protection status: disabled.") == .disabled)
}

@Test func parseSIPUnknown() {
    #expect(parseSIPStatus("whatever") == .unknown)
}

@Test func parseSwVersProductAndBuild() {
    let sample = """
    ProductName:\t\tmacOS
    ProductVersion:\t\t26.4.1
    BuildVersion:\t\t25E253
    """
    let v = parseSwVers(sample)
    #expect(v.productName == "macOS")
    #expect(v.productVersion == "26.4.1")
    #expect(v.buildVersion == "25E253")
}
```

- [ ] **Step 6.2: Run the tests and verify they fail**

```bash
swift test --filter MachineInfoTests
```
Expected: compile failure.

- [ ] **Step 6.3: Implement `MachineInfo.swift`**

Create `Sources/embercap/MachineInfo.swift`:

```swift
import Foundation

enum SIPStatus: String, Sendable, Equatable, Codable {
    case enabled, disabled, unknown
}

struct SwVersInfo: Sendable, Equatable, Codable {
    let productName: String
    let productVersion: String
    let buildVersion: String
}

struct MachineInfo: Sendable, Equatable, Codable {
    let model: String               // hw.model, e.g. "MacBookPro16,1"
    let cpuBrand: String            // machdep.cpu.brand_string
    let arch: String                // uname -m equivalent
    let kernel: String              // full uname -a first line
    let swVers: SwVersInfo
    let sip: SIPStatus
}

func parseSIPStatus(_ raw: String) -> SIPStatus {
    let lower = raw.lowercased()
    if lower.contains("enabled") { return .enabled }
    if lower.contains("disabled") { return .disabled }
    return .unknown
}

func parseSwVers(_ raw: String) -> SwVersInfo {
    var product = ""
    var version = ""
    var build = ""
    for line in raw.split(whereSeparator: { $0.isNewline }) {
        let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { continue }
        let k = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let v = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        switch k {
        case "ProductName": product = v
        case "ProductVersion": version = v
        case "BuildVersion": build = v
        default: break
        }
    }
    return SwVersInfo(productName: product, productVersion: version, buildVersion: build)
}

enum MachineInfoReader {
    static func collect() -> MachineInfo {
        return MachineInfo(
            model: sysctlString("hw.model") ?? "unknown",
            cpuBrand: sysctlString("machdep.cpu.brand_string") ?? "unknown",
            arch: sysctlString("hw.machine") ?? "unknown",
            kernel: runCapture("/usr/bin/uname", ["-a"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown",
            swVers: parseSwVers(runCapture("/usr/bin/sw_vers", []) ?? ""),
            sip: parseSIPStatus(runCapture("/usr/bin/csrutil", ["status"]) ?? "")
        )
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        if sysctlbyname(name, nil, &size, nil, 0) != 0 { return nil }
        var buf = [CChar](repeating: 0, count: size)
        if sysctlbyname(name, &buf, &size, nil, 0) != 0 { return nil }
        return String(cString: buf)
    }

    private static func runCapture(_ path: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
```

- [ ] **Step 6.4: Run the tests and verify they pass**

```bash
swift test --filter MachineInfoTests
```
Expected: 4 tests passing.

- [ ] **Step 6.5: Commit**

```bash
git add Sources/embercap/MachineInfo.swift Tests/embercapTests/MachineInfoTests.swift
git -c commit.gpgsign=false commit -m "feat(machine): fingerprint collector with SIP + sw_vers parser tests"
```

---

## Task 7 — `BatteryStatus` module

**Why:** `status` and `diag` both need a populated battery snapshot pulled from the supported public APIs plus the richer `AppleSmartBattery` IORegistry properties.

**Files:**
- Create: `Sources/embercap/BatteryStatus.swift`

No unit tests for this module — all paths require real IOKit and a present battery. A smoke test is added in Task 9 once the CLI is wired.

- [ ] **Step 7.1: Implement `BatteryStatus.swift`**

Create `Sources/embercap/BatteryStatus.swift`:

```swift
import Foundation
import IOKit
import IOKit.ps

struct BatterySnapshot: Sendable, Equatable, Codable {
    let isPresent: Bool
    let isCharging: Bool?
    let isCharged: Bool?
    let externalConnected: Bool?
    let powerSourceState: String?
    let currentCapacityPercent: Int?      // from IOPS (normalized 0-100)
    let timeToFullMinutes: Int?
    let timeToEmptyMinutes: Int?
    let serial: String?
    let cycleCount: Int?
    let designCapacityMAh: Int?
    let maxCapacityMAh: Int?
    let currentCapacityMAh: Int?
    let temperatureCelsius: Double?       // AppleSmartBattery.Temperature / 100
    let fullyCharged: Bool?
    let notChargingReason: Int?
}

enum BatteryStatusReader {
    static func collect() -> BatterySnapshot {
        let ips = readIOPS()
        let reg = readAppleSmartBattery()
        return BatterySnapshot(
            isPresent: ips.isPresent ?? reg.batteryInstalled ?? false,
            isCharging: ips.isCharging ?? reg.isCharging,
            isCharged: ips.isCharged,
            externalConnected: reg.externalConnected,
            powerSourceState: ips.powerSourceState,
            currentCapacityPercent: ips.currentCapacityPercent,
            timeToFullMinutes: ips.timeToFull,
            timeToEmptyMinutes: ips.timeToEmpty,
            serial: ips.serial ?? reg.serial,
            cycleCount: reg.cycleCount,
            designCapacityMAh: reg.designCapacity,
            maxCapacityMAh: reg.maxCapacity,
            currentCapacityMAh: reg.currentCapacity,
            temperatureCelsius: reg.temperature.map { Double($0) / 100.0 },
            fullyCharged: reg.fullyCharged,
            notChargingReason: reg.notChargingReason
        )
    }

    // --- IOPowerSources ---
    private struct IOPSFields {
        var isPresent: Bool?
        var isCharging: Bool?
        var isCharged: Bool?
        var powerSourceState: String?
        var currentCapacityPercent: Int?
        var timeToFull: Int?
        var timeToEmpty: Int?
        var serial: String?
    }

    private static func readIOPS() -> IOPSFields {
        var f = IOPSFields()
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
              let source = list.first,
              let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] else {
            return f
        }
        f.isPresent = desc["Is Present"] as? Bool
        f.isCharging = desc["Is Charging"] as? Bool
        f.isCharged = desc["Is Charged"] as? Bool
        f.powerSourceState = desc["Power Source State"] as? String
        f.currentCapacityPercent = desc["Current Capacity"] as? Int
        if let t = desc["Time to Full Charge"] as? Int, t > 0 { f.timeToFull = t }
        if let t = desc["Time to Empty"] as? Int, t > 0 { f.timeToEmpty = t }
        f.serial = desc["Hardware Serial Number"] as? String
        return f
    }

    // --- AppleSmartBattery IORegistry ---
    private struct RegFields {
        var batteryInstalled: Bool?
        var isCharging: Bool?
        var externalConnected: Bool?
        var serial: String?
        var cycleCount: Int?
        var designCapacity: Int?
        var maxCapacity: Int?
        var currentCapacity: Int?
        var temperature: Int?
        var fullyCharged: Bool?
        var notChargingReason: Int?
    }

    private static func readAppleSmartBattery() -> RegFields {
        var f = RegFields()
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if service == 0 { return f }
        defer { IOObjectRelease(service) }
        var propsRef: Unmanaged<CFMutableDictionary>?
        let kr = IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0)
        guard kr == kIOReturnSuccess, let props = propsRef?.takeRetainedValue() as? [String: Any] else {
            return f
        }
        f.batteryInstalled = props["BatteryInstalled"] as? Bool
        f.isCharging = props["IsCharging"] as? Bool
        f.externalConnected = props["ExternalConnected"] as? Bool
        f.serial = props["Serial"] as? String
        f.cycleCount = props["CycleCount"] as? Int
        f.designCapacity = props["DesignCapacity"] as? Int
        f.maxCapacity = props["MaxCapacity"] as? Int
        f.currentCapacity = props["CurrentCapacity"] as? Int
        f.temperature = props["Temperature"] as? Int
        f.fullyCharged = props["FullyCharged"] as? Bool
        if let charger = props["ChargerData"] as? [String: Any] {
            f.notChargingReason = charger["NotChargingReason"] as? Int
        }
        return f
    }
}

func renderBatteryHuman(_ b: BatterySnapshot) -> String {
    var out = "== battery status ==\n"
    func line(_ label: String, _ v: Any?) {
        if let v = v { out += "  \(pad(label, 22)) \(v)\n" }
    }
    line("present", b.isPresent)
    line("power source state", b.powerSourceState)
    line("charging", b.isCharging)
    line("fully charged", b.fullyCharged)
    line("external connected", b.externalConnected)
    line("current %", b.currentCapacityPercent.map { "\($0)%" })
    line("design mAh", b.designCapacityMAh)
    line("max mAh", b.maxCapacityMAh)
    line("current mAh", b.currentCapacityMAh)
    line("cycle count", b.cycleCount)
    line("temperature", b.temperatureCelsius.map { String(format: "%.1f °C", $0) })
    line("time to full (min)", b.timeToFullMinutes)
    line("time to empty (min)", b.timeToEmptyMinutes)
    line("not charging reason", b.notChargingReason)
    line("serial", b.serial)
    return out
}
```

- [ ] **Step 7.2: Verify it builds**

```bash
swift build
```
Expected: success with no new warnings.

- [ ] **Step 7.3: Commit**

```bash
git add Sources/embercap/BatteryStatus.swift
git -c commit.gpgsign=false commit -m "feat(battery): IOPSCopy + AppleSmartBattery snapshot + human renderer"
```

---

## Task 8 — `Diag` module: aggregate + JSON + Markdown

**Why:** Spec §5.3 requires a machine-readable and human-readable report that bundles machine info, battery snapshot, and probe results. JSON is `Codable` straightforward; Markdown is a small string builder.

**Files:**
- Create: `Sources/embercap/Diag.swift`
- Create: `Sources/embercap/Version.swift`
- Create: `Tests/embercapTests/DiagEncoderTests.swift`

- [ ] **Step 8.1: Write failing encoder tests**

Create `Tests/embercapTests/DiagEncoderTests.swift`:

```swift
import Testing
import Foundation
@testable import embercap

private func fixtureDiag() -> DiagReport {
    DiagReport(
        schemaVersion: 1,
        generatedAt: "2026-04-23T00:00:00Z",
        tool: DiagTool(name: "embercap", version: "0.1.0", commitSHA: nil),
        machine: MachineInfo(
            model: "MacBookPro16,1",
            cpuBrand: "Intel(R) Core(TM) i9-9880H CPU @ 2.30GHz",
            arch: "x86_64",
            kernel: "Darwin … x86_64",
            swVers: SwVersInfo(productName: "macOS", productVersion: "26.4.1", buildVersion: "25E253"),
            sip: .enabled
        ),
        battery: BatterySnapshot(
            isPresent: true, isCharging: false, isCharged: true, externalConnected: true,
            powerSourceState: "AC Power", currentCapacityPercent: 100,
            timeToFullMinutes: nil, timeToEmptyMinutes: nil,
            serial: "F5D03110XY5K7LQC8", cycleCount: 160,
            designCapacityMAh: 8790, maxCapacityMAh: 7484, currentCapacityMAh: 7484,
            temperatureCelsius: 30.75, fullyCharged: true, notChargingReason: 1
        ),
        probe: ProbeReport(
            matchedService: true,
            openKr: 0,
            openSessionKr: 0,
            keyResults: [ProbeKeyResult(key: "TB0T", infoKr: kIOReturnBadArgument, readKr: nil)],
            verdict: .legacyAbiUnavailable
        )
    )
}

@Test func jsonEncoderEmitsTopLevelKeys() throws {
    let data = try encodeDiagJSON(fixtureDiag())
    let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(obj != nil)
    let keys = Set((obj ?? [:]).keys)
    #expect(keys == ["schemaVersion", "generatedAt", "tool", "machine", "battery", "probe"])
}

@Test func jsonEncoderPinsSchemaVersion() throws {
    let data = try encodeDiagJSON(fixtureDiag())
    let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(obj?["schemaVersion"] as? Int == 1)
}

@Test func markdownReportHasRequiredSections() {
    let md = renderDiagMarkdown(fixtureDiag())
    for header in ["# embercap diagnostic report", "## Machine", "## Battery", "## Probe", "verdict: `legacy-abi-unavailable`"] {
        #expect(md.contains(header))
    }
}
```

- [ ] **Step 8.2: Run the tests and verify they fail**

```bash
swift test --filter DiagEncoderTests
```
Expected: compile failure.

- [ ] **Step 8.3: Implement `Version.swift`**

Create `Sources/embercap/Version.swift`:

```swift
import Foundation

enum Version {
    static let string = "0.1.0"

    /// Runtime lookup of the embercap source tree's git HEAD, best-effort.
    /// Returns nil if git is unavailable or the binary is not executed from
    /// inside the source tree.
    static func commitSHA() -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["rev-parse", "HEAD"]
        p.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (s?.isEmpty == false) ? s : nil
    }
}
```

- [ ] **Step 8.4: Implement `Diag.swift`**

Create `Sources/embercap/Diag.swift`:

```swift
import Foundation

struct DiagTool: Sendable, Equatable, Codable {
    let name: String
    let version: String
    let commitSHA: String?
}

struct DiagReport: Sendable, Equatable, Codable {
    let schemaVersion: Int
    let generatedAt: String
    let tool: DiagTool
    let machine: MachineInfo
    let battery: BatterySnapshot
    let probe: ProbeReport
}

// ProbeReport is already Sendable/Equatable; make it Codable here.
extension ProbeKeyResult: Codable {}
extension ProbeReport: Codable {}

enum DiagFormat: String { case json, markdown }

enum DiagCollector {
    static func collect() -> DiagReport {
        let now = ISO8601DateFormatter().string(from: Date())
        return DiagReport(
            schemaVersion: 1,
            generatedAt: now,
            tool: DiagTool(name: "embercap", version: Version.string, commitSHA: Version.commitSHA()),
            machine: MachineInfoReader.collect(),
            battery: BatteryStatusReader.collect(),
            probe: ProbeRunner.run()
        )
    }
}

func encodeDiagJSON(_ r: DiagReport) throws -> Data {
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try enc.encode(r)
}

func renderDiagMarkdown(_ r: DiagReport) -> String {
    var s = "# embercap diagnostic report\n\n"
    s += "Generated: `\(r.generatedAt)`  \n"
    s += "Schema version: `\(r.schemaVersion)`  \n"
    s += "Tool: `\(r.tool.name) \(r.tool.version)` (commit `\(r.tool.commitSHA ?? "dev")`)\n\n"

    s += "## Machine\n\n"
    s += "- Model: `\(r.machine.model)`\n"
    s += "- CPU: `\(r.machine.cpuBrand)`\n"
    s += "- Arch: `\(r.machine.arch)`\n"
    s += "- macOS: `\(r.machine.swVers.productVersion) (\(r.machine.swVers.buildVersion))`\n"
    s += "- Kernel: `\(r.machine.kernel)`\n"
    s += "- SIP: `\(r.machine.sip.rawValue)`\n\n"

    s += "## Battery\n\n"
    let b = r.battery
    s += "- present: \(b.isPresent)\n"
    s += "- power source: \(b.powerSourceState ?? "n/a")\n"
    s += "- charging: \(b.isCharging.map(String.init(describing:)) ?? "n/a")\n"
    s += "- current %: \(b.currentCapacityPercent.map { "\($0)%" } ?? "n/a")\n"
    s += "- cycle count: \(b.cycleCount.map(String.init) ?? "n/a")\n"
    s += "- design/max/current mAh: "
    s += "\(b.designCapacityMAh.map(String.init) ?? "?") / "
    s += "\(b.maxCapacityMAh.map(String.init) ?? "?") / "
    s += "\(b.currentCapacityMAh.map(String.init) ?? "?")\n"
    s += "- temperature: \(b.temperatureCelsius.map { String(format: "%.1f °C", $0) } ?? "n/a")\n"
    s += "- serial: `\(b.serial ?? "n/a")`\n\n"

    s += "## Probe\n\n"
    s += "verdict: `\(r.probe.verdict.rawValue)`\n\n"
    s += "- matched AppleSMC: \(r.probe.matchedService)\n"
    s += "- IOServiceOpen: \(r.probe.openKr.map { machErrorString($0) } ?? "n/a")\n"
    s += "- openSession (sel 0): \(r.probe.openSessionKr.map { machErrorString($0) } ?? "n/a")\n\n"
    s += "| key  | getKeyInfo | readKey |\n"
    s += "|------|------------|---------|\n"
    for kr in r.probe.keyResults {
        let readCell = kr.readKr.map { machErrorString($0) } ?? "(skipped)"
        s += "| `\(kr.key)` | \(machErrorString(kr.infoKr)) | \(readCell) |\n"
    }
    return s
}
```

- [ ] **Step 8.5: Run the tests and verify they pass**

```bash
swift test --filter DiagEncoderTests
```
Expected: 3 tests passing.

- [ ] **Step 8.6: Commit**

```bash
git add Sources/embercap/Diag.swift Sources/embercap/Version.swift Tests/embercapTests/DiagEncoderTests.swift
git -c commit.gpgsign=false commit -m "feat(diag): Codable aggregate + JSON + Markdown renderers with tests"
```

---

## Task 9 — CLI dispatcher: `help`, `version`, `status`, `probe`, `diag`

**Why:** Wire the modules behind the five commands the spec lists. Keep argv parsing trivial: no third-party dependency.

**Files:**
- Replace: `Sources/embercap/embercap.swift`

- [ ] **Step 9.1: Replace `Sources/embercap/embercap.swift`**

Overwrite `Sources/embercap/embercap.swift` with exactly:

```swift
import Foundation

@main
struct Embercap {
    static let usage = """
    embercap — read-only battery diagnostic CLI for Intel Mac / macOS 26
    Usage:
      embercap status          Human-readable battery summary
      embercap probe           Feasibility probe of AppleSMC legacy ABI
      embercap diag [--format=json|markdown]
                               Machine-readable diagnostic report
      embercap version         Build + machine fingerprint
      embercap help            This message
    """

    static func main() {
        setlinebuf(stdout)
        let args = Array(CommandLine.arguments.dropFirst())
        guard let cmd = args.first else {
            print(usage)
            return
        }
        let rest = Array(args.dropFirst())
        switch cmd {
        case "help", "-h", "--help":
            print(usage)
        case "version", "--version":
            runVersion()
        case "status":
            runStatus()
        case "probe":
            runProbe()
        case "diag":
            runDiag(rest)
        default:
            FileHandle.standardError.write(Data("unknown command: \(cmd)\n".utf8))
            print(usage)
            exit(64)
        }
    }

    static func runVersion() {
        let m = MachineInfoReader.collect()
        print("embercap \(Version.string) (\(Version.commitSHA() ?? "dev"))")
        print("host: \(m.model) / \(m.arch) / macOS \(m.swVers.productVersion) (\(m.swVers.buildVersion)) / SIP \(m.sip.rawValue)")
    }

    static func runStatus() {
        let snap = BatteryStatusReader.collect()
        print(renderBatteryHuman(snap), terminator: "")
    }

    static func runProbe() {
        let r = ProbeRunner.run()
        print(renderProbeHuman(r), terminator: "")
    }

    static func runDiag(_ rest: [String]) {
        var format: DiagFormat = .json
        for arg in rest {
            if arg.hasPrefix("--format=") {
                let v = String(arg.dropFirst("--format=".count))
                guard let parsed = DiagFormat(rawValue: v) else {
                    FileHandle.standardError.write(Data("unknown format: \(v)\n".utf8))
                    exit(64)
                }
                format = parsed
            } else {
                FileHandle.standardError.write(Data("unknown arg: \(arg)\n".utf8))
                exit(64)
            }
        }
        let r = DiagCollector.collect()
        switch format {
        case .json:
            do {
                let data = try encodeDiagJSON(r)
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
            } catch {
                FileHandle.standardError.write(Data("diag json encode failed: \(error)\n".utf8))
                exit(1)
            }
        case .markdown:
            print(renderDiagMarkdown(r), terminator: "")
        }
    }
}
```

- [ ] **Step 9.2: Update the dispatcher smoke test in `embercapTests.swift`**

Overwrite `Tests/embercapTests/embercapTests.swift`:

```swift
import Testing
@testable import embercap

@Test func usageBannerMentionsAllCommands() {
    let banner = Embercap.usage
    for cmd in ["status", "probe", "diag", "version", "help"] {
        #expect(banner.contains(cmd))
    }
}
```

- [ ] **Step 9.3: Run the full test suite**

```bash
swift test
```
Expected: all tests pass.

- [ ] **Step 9.4: Smoke-run each command on the target machine**

```bash
swift build
./.build/debug/embercap help
./.build/debug/embercap version
./.build/debug/embercap status
./.build/debug/embercap probe
./.build/debug/embercap diag --format=json | python3 -m json.tool | head
./.build/debug/embercap diag --format=markdown | head
```
Expected:
- `help` prints the banner, exits 0
- `version` prints tool + host line, exits 0
- `status` prints populated battery lines, exits 0
- `probe` prints the ordered report ending with `verdict: legacy-abi-unavailable`, exits 0
- `diag --format=json` emits valid JSON with the six top-level keys
- `diag --format=markdown` emits a document starting with `# embercap diagnostic report`

- [ ] **Step 9.5: Commit**

```bash
git add Sources/embercap/embercap.swift Tests/embercapTests/embercapTests.swift
git -c commit.gpgsign=false commit -m "feat(cli): dispatcher for help/version/status/probe/diag"
```

---

## Task 10 — README, diag schema, captured samples

**Why:** Spec §9 pins a specific README order and acceptance criterion #7 requires sample transcripts. This locks current-machine evidence in a form that regressions against it are easy to spot.

**Files:**
- Create: `README.md`
- Create: `docs/diag-schema.md`
- Create: `docs/samples/probe-macos26-mbp161.txt`
- Create: `docs/samples/diag-macos26-mbp161.json`
- Create: `docs/samples/diag-macos26-mbp161.md`

- [ ] **Step 10.1: Create `README.md`**

Write `README.md`:

```markdown
# embercap

**embercap is not a charge-control tool.**

It is a **read-only diagnostic CLI** that explains *why* AlDente-style charge
control is not currently implementable on this Intel Mac and this macOS
version. It reads battery state from public APIs and reports, with evidence,
how the legacy AppleSMC userland ABI (the one bclm / SMCKit / iStats used)
behaves on the current OS.

## Why this tool exists

Target machine: MacBookPro16,1 (Intel Core i9-9880H), macOS 26.4.1, SIP enabled.

The legacy selector-2 `SMCKeyData_t` ABI used by every known open-source SMC
library returns `kIOReturnBadArgument` for every key on this machine — even
sanity keys like `TB0T` (battery temperature) and `BNum` (battery count) that
must exist on any Intel Mac firmware. `IOServiceOpen(AppleSMC)` still
succeeds and `openSession` (selector 0) still returns success, but the struct
call used to read or write any key is rejected at the driver. Matching
`AppleSMC` exposes `IOUserClientClass = "AppleSMCClient"` and multiple live
client instances — the userclient is alive, Apple's own daemons drive it via
a modern (private, undocumented) dispatch, but the legacy ABI is gone.

This is consistent with zackelia/bclm's note that bclm stopped working on
macOS ≥ 15; we are on macOS 26 and the evidence is broader (reads also
rejected, not just writes).

See `docs/superpowers/specs/2026-04-23-embercap-read-only-diag-cli-design.md`
for the full evidence table and design rationale.

## Usage

```
embercap status                         Human-readable battery summary
embercap probe                          Labeled AppleSMC legacy-ABI probe
embercap diag [--format=json|markdown]  Machine-readable diagnostic report
embercap version                        Tool + host fingerprint
embercap help                           Usage text
```

Sample transcripts from this target machine are committed under
`docs/samples/`.

## Build

```
swift build
./.build/debug/embercap help
```

Requires Swift 6.3+ and the Xcode Command Line Tools on macOS. No third-party
dependencies.

## Research notes

Reverse-engineering the modern `AppleSMCClient` dispatch (e.g. via
`class-dump` on `powerd`, or comparison against VirtualSMC) is explicitly
out of scope for this `main` tool — see spec §4. Any such work lives in a
separate `research/` branch and does not enter `main` unless the resulting
write path is stable across multiple OS point releases and can be signed
without a private entitlement.
```

- [ ] **Step 10.2: Create `docs/diag-schema.md`**

Write `docs/diag-schema.md`:

```markdown
# diag JSON schema (version 1)

`embercap diag --format=json` emits a document with these top-level keys:

| key | type | notes |
| --- | --- | --- |
| `schemaVersion` | int | currently `1`; bump on incompatible changes |
| `generatedAt` | string | ISO 8601 timestamp (UTC) |
| `tool` | object | `{ name, version, commitSHA? }` |
| `machine` | object | `MachineInfo` — model, cpu, arch, kernel, sw_vers, sip |
| `battery` | object | `BatterySnapshot` — see `BatteryStatus.swift` |
| `probe` | object | `ProbeReport` — see `ProbeSMC.swift` |

`probe.verdict` is one of: `legacy-abi-unavailable`, `blocked-by-policy`,
`partial-success`, `inconclusive`. See spec §5.2.

`probe.keyResults` is an array of `{ key, infoKr, readKr? }` per probed key,
where `infoKr` and `readKr` are raw `kern_return_t` integers.
```

- [ ] **Step 10.3: Capture sample transcripts from the target machine**

```bash
./.build/debug/embercap probe > docs/samples/probe-macos26-mbp161.txt
./.build/debug/embercap diag --format=json > docs/samples/diag-macos26-mbp161.json
./.build/debug/embercap diag --format=markdown > docs/samples/diag-macos26-mbp161.md
```

Sanity-check the captures:
```bash
grep -q 'verdict: legacy-abi-unavailable' docs/samples/probe-macos26-mbp161.txt
python3 -m json.tool < docs/samples/diag-macos26-mbp161.json > /dev/null
grep -q 'verdict: `legacy-abi-unavailable`' docs/samples/diag-macos26-mbp161.md
echo "all three sanity checks passed"
```

Expected: the echo line prints.

- [ ] **Step 10.4: Commit**

```bash
git add README.md docs/diag-schema.md docs/samples/
git -c commit.gpgsign=false commit -m "docs: README per spec §9, diag schema, target-machine samples"
```

---

## Task 11 — Write-path guardrail + final acceptance sweep

**Why:** Spec acceptance criterion #8 requires a grep for write-path references in `Sources/` to return zero matches in `main`. Bake that into CI-style verification plus run through all eight acceptance criteria once end-to-end.

**Files:**
- Create: `scripts/check-no-write-path.sh`
- Modify: `Tests/embercapTests/embercapTests.swift` (add a test that invokes the script)

- [ ] **Step 11.1: Create the guardrail script**

Create `scripts/check-no-write-path.sh`:

```bash
#!/usr/bin/env bash
# Spec §11 acceptance criterion #8: main must contain no write-path code.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
hits=$(cd "$root" && grep -REn 'writeKey|kSMCWriteKey|\.writeKey|selector=6|selector: *6' Sources/ || true)
if [ -n "$hits" ]; then
    echo "FAIL: write-path references found in Sources/:" >&2
    echo "$hits" >&2
    exit 1
fi
echo "ok: no write-path references in Sources/"
```

Make it executable:
```bash
chmod +x scripts/check-no-write-path.sh
```

- [ ] **Step 11.2: Add a test that invokes the guardrail script**

Append to `Tests/embercapTests/embercapTests.swift`:

```swift
import Foundation

@Test func noWritePathReferencesInSources() throws {
    // Repository root relative to this test file.
    // #filePath is absolute; walk up to find the repo root (contains Package.swift).
    let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    var root = here
    while !FileManager.default.fileExists(atPath: root.appendingPathComponent("Package.swift").path) {
        let parent = root.deletingLastPathComponent()
        #expect(parent.path != root.path, "could not find repo root from \(here.path)")
        if parent.path == root.path { return }
        root = parent
    }
    let script = root.appendingPathComponent("scripts/check-no-write-path.sh").path
    #expect(FileManager.default.fileExists(atPath: script))

    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/bash")
    p.arguments = [script]
    p.currentDirectoryURL = root
    let out = Pipe()
    let err = Pipe()
    p.standardOutput = out
    p.standardError = err
    try p.run()
    p.waitUntilExit()
    #expect(p.terminationStatus == 0,
            "guardrail failed: \(String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")")
}
```

- [ ] **Step 11.3: Run the full test suite**

```bash
swift test
```
Expected: all tests pass, including the guardrail.

- [ ] **Step 11.4: Walk the acceptance criteria (spec §11)**

Run each check and confirm pass:

1. `swift build` — run; expect success
2. `./.build/debug/embercap status` — run; expect populated output
3. `./.build/debug/embercap probe` — run; expect exit 0 and `verdict: legacy-abi-unavailable`
4. `./.build/debug/embercap diag --format=json | python3 -m json.tool > /dev/null` — expect success
5. `./.build/debug/embercap diag --format=markdown | head -1` — expect `# embercap diagnostic report`
6. Inspect `README.md` — confirm the order: (a) "not a charge-control tool", (b) "explains why charge control is not implementable", (c) evidence summary, (d) usage, (e) research notes
7. `ls docs/samples/` — expect the three captured files
8. `bash scripts/check-no-write-path.sh` — expect `ok: no write-path references in Sources/`

- [ ] **Step 11.5: Commit**

```bash
git add scripts/check-no-write-path.sh Tests/embercapTests/embercapTests.swift
git -c commit.gpgsign=false commit -m "test: write-path guardrail grep + acceptance sweep"
```

---

## Self-review (executed after writing this plan)

Spec coverage walk (each spec section vs. a task that implements it):

- §1 Purpose — Task 10 (README opening), Task 9 (usage banner)
- §2 Evidence — documented in spec; plan references via README (Task 10) and sample transcripts (Task 10)
- §3 Why no enable/disable/target — enforced by Task 11 guardrail (grep), documented in Task 10 README
- §4 Research-branch carve-out — Task 10 README "Research notes" section
- §5.1 `status` — Task 7 (reader) + Task 9 (dispatcher wiring)
- §5.2 `probe` labeled steps + four-way verdict — Task 4 (classifier) + Task 5 (runner + human render) + Task 9 (wiring)
- §5.3 `diag` JSON + Markdown — Task 8 + Task 9
- §5.4 `version` — Task 8 (Version), Task 9 (runVersion)
- §6 Architecture one-responsibility-per-file — File structure table + one task per file
- §7 Error handling — `machErrorString` in Task 2, used everywhere; `probe` exit 0 on legacy-ABI verdict is in Task 5 runner + Task 9 dispatcher
- §8 Testing (unit + integration + samples) — Tasks 2/3/4/6/8 unit, Task 5 integration, Task 10 samples
- §9 README order — Task 10 step 10.1
- §10 Out of scope — not implemented by construction; guardrail in Task 11
- §11 Acceptance criteria — Task 11 step 11.4 runs each

Placeholder scan: no "TBD", no "etc.", every code step has complete code. All referenced types (`SMCKeyData_t`, `ProbeKeyResult`, `ProbeReport`, `ProbeVerdict`, `BatterySnapshot`, `MachineInfo`, `DiagReport`, `DiagFormat`) are defined in an explicit earlier task.

Type-consistency scan: `classifyProbe(_:)` signature in Task 4 matches its call site in Task 5. `SMC.call(_:)` returns `(kern_return_t, SMCKeyData_t)` in Task 3 and is unpacked the same way in Task 5. `ProbeReport` fields used in `renderProbeHuman` and `renderDiagMarkdown` (Tasks 5 and 8) match the declaration in Task 5. Top-level JSON keys expected in `DiagEncoderTests` (Task 8 step 8.1) exactly match the `DiagReport` stored properties in step 8.4.
