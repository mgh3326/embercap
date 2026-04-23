import Foundation

@main
struct Embercap {
    static let usage = """
    embercap — read-only battery diagnostic CLI for Intel Mac / macOS 26
    Usage:
      embercap status          Human-readable battery summary
      embercap probe           Feasibility probe of AppleSMC legacy ABI
      embercap diag [--format=json|markdown]
                               Machine-readable diagnostic report
      embercap version         Build + machine fingerprint
      embercap help            This message
    """

    static func main() {
        setlinebuf(stdout)
        let args = Array(CommandLine.arguments.dropFirst())
        guard let cmd = args.first else {
            print(usage)
            return
        }
        let rest = Array(args.dropFirst())
        switch cmd {
        case "help", "-h", "--help":
            print(usage)
        case "version", "--version":
            runVersion()
        case "status":
            runStatus()
        case "probe":
            runProbe()
        case "diag":
            runDiag(rest)
        default:
            FileHandle.standardError.write(Data("unknown command: \(cmd)\n".utf8))
            print(usage)
            exit(64)
        }
    }

    static func runVersion() {
        let m = MachineInfoReader.collect()
        print("embercap \(Version.string) (\(Version.commitSHA() ?? "dev"))")
        print("host: \(m.model) / \(m.arch) / macOS \(m.swVers.productVersion) (\(m.swVers.buildVersion)) / SIP \(m.sip.rawValue)")
    }

    static func runStatus() {
        let snap = BatteryStatusReader.collect()
        print(renderBatteryHuman(snap), terminator: "")
    }

    static func runProbe() {
        let r = ProbeRunner.run()
        print(renderProbeHuman(r), terminator: "")
    }

    static func runDiag(_ rest: [String]) {
        var format: DiagFormat = .json
        for arg in rest {
            if arg.hasPrefix("--format=") {
                let v = String(arg.dropFirst("--format=".count))
                guard let parsed = DiagFormat(rawValue: v) else {
                    FileHandle.standardError.write(Data("unknown format: \(v)\n".utf8))
                    exit(64)
                }
                format = parsed
            } else {
                FileHandle.standardError.write(Data("unknown arg: \(arg)\n".utf8))
                exit(64)
            }
        }
        let r = DiagCollector.collect()
        switch format {
        case .json:
            do {
                let data = try encodeDiagJSON(r)
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
            } catch {
                FileHandle.standardError.write(Data("diag json encode failed: \(error)\n".utf8))
                exit(1)
            }
        case .markdown:
            print(renderDiagMarkdown(r), terminator: "")
        }
    }
}
