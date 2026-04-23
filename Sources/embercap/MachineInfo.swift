import Foundation

enum SIPStatus: String, Sendable, Equatable, Codable {
    case enabled, disabled, unknown
}

struct SwVersInfo: Sendable, Equatable, Codable {
    let productName: String
    let productVersion: String
    let buildVersion: String
}

struct MachineInfo: Sendable, Equatable, Codable {
    let model: String
    let cpuBrand: String
    let arch: String
    let kernel: String
    let swVers: SwVersInfo
    let sip: SIPStatus
}

func parseSIPStatus(_ raw: String) -> SIPStatus {
    let lower = raw.lowercased()
    if lower.contains("enabled") { return .enabled }
    if lower.contains("disabled") { return .disabled }
    return .unknown
}

func parseSwVers(_ raw: String) -> SwVersInfo {
    var product = ""
    var version = ""
    var build = ""
    for line in raw.split(whereSeparator: { $0.isNewline }) {
        let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { continue }
        let k = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let v = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        switch k {
        case "ProductName": product = v
        case "ProductVersion": version = v
        case "BuildVersion": build = v
        default: break
        }
    }
    return SwVersInfo(productName: product, productVersion: version, buildVersion: build)
}

enum MachineInfoReader {
    static func collect() -> MachineInfo {
        return MachineInfo(
            model: sysctlString("hw.model") ?? "unknown",
            cpuBrand: sysctlString("machdep.cpu.brand_string") ?? "unknown",
            arch: sysctlString("hw.machine") ?? "unknown",
            kernel: runCapture("/usr/bin/uname", ["-a"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown",
            swVers: parseSwVers(runCapture("/usr/bin/sw_vers", []) ?? ""),
            sip: parseSIPStatus(runCapture("/usr/bin/csrutil", ["status"]) ?? "")
        )
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        if sysctlbyname(name, nil, &size, nil, 0) != 0 { return nil }
        var buf = [CChar](repeating: 0, count: size)
        if sysctlbyname(name, &buf, &size, nil, 0) != 0 { return nil }
        return String(cString: buf)
    }

    private static func runCapture(_ path: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
