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
        switch cmd {
        case "help", "-h", "--help":
            print(usage)
        default:
            FileHandle.standardError.write(Data("unknown command: \(cmd)\n".utf8))
            print(usage)
            exit(64) // EX_USAGE
        }
    }
}
