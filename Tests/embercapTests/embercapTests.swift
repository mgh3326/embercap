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
