import Testing
import Foundation
import IOKit
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
