import Foundation
import IOKit

struct ProbeKeyResult: Sendable, Equatable {
    let key: String
    let infoKr: kern_return_t
    let readKr: kern_return_t?
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
