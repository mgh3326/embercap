import Foundation
import IOKit

struct ProbeKeyResult: Sendable, Equatable, Codable {
    let key: String
    let infoKr: kern_return_t
    let readKr: kern_return_t?
}

enum ProbeVerdict: String, Sendable, Equatable, Codable {
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

struct ProbeReport: Sendable, Equatable, Codable {
    let matchedService: Bool
    let openKr: kern_return_t?
    let openSessionKr: kern_return_t?
    let keyResults: [ProbeKeyResult]
    let verdict: ProbeVerdict
}

enum ProbeRunner {
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
