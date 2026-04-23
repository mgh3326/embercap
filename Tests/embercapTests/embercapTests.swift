import Testing
import Foundation
@testable import embercap

@Test func usageBannerMentionsAllCommands() {
    let banner = Embercap.usage
    for cmd in ["status", "probe", "diag", "version", "help"] {
        #expect(banner.contains(cmd))
    }
}

@Test func noWritePathReferencesInSources() throws {
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
