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
