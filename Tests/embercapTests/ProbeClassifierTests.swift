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
