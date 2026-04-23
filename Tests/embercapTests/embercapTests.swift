import Testing
@testable import embercap

@Test func usageBannerMentionsAllCommands() {
    let banner = Embercap.usage
    for cmd in ["status", "probe", "diag", "version", "help"] {
        #expect(banner.contains(cmd))
    }
}
