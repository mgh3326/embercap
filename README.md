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
dependencies beyond `swift-testing` (fetched by SwiftPM for tests only).

## Research notes

Reverse-engineering the modern `AppleSMCClient` dispatch (e.g. via
`class-dump` on `powerd`, or comparison against VirtualSMC) is explicitly
out of scope for this `main` tool — see spec §4. Any such work lives in a
separate `research/` branch and does not enter `main` unless the resulting
write path is stable across multiple OS point releases and can be signed
without a private entitlement.
