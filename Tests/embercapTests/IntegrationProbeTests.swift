import Testing
import IOKit
@testable import embercap

@Test(.tags(.hardware))
func probeOnThisIntelMacReportsLegacyAbiUnavailable() {
    let r = ProbeRunner.run()
    #expect(r.matchedService == true)
    #expect(r.openKr == kIOReturnSuccess)
    #expect(r.verdict == .legacyAbiUnavailable)
    #expect(r.keyResults.count == ProbeRunner.probeKeys.count)
}

extension Tag {
    @Tag static var hardware: Self
}
