import Foundation
import IOKit

struct SMCKeyData_vers_t {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

struct SMCKeyData_pLimitData_t {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

struct SMCKeyData_keyInfo_t {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

struct SMCKeyData_t {
    var key: UInt32 = 0
    var vers = SMCKeyData_vers_t()
    var pLimitData = SMCKeyData_pLimitData_t()
    var keyInfo = SMCKeyData_keyInfo_t()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    ) = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}

enum SMCSubCommand: UInt8 {
    case getKeyInfo = 9
    case readKey = 5
}

// kSMCHandleYPCEvent: the legacy dispatch selector used by bclm / SMCKit /
// iStats to drive structured key access. On macOS >= 15 this path has been
// observed to return kIOReturnBadArgument for every key. See spec §2 for the
// Intel-machine evidence.
let kSMCUserClientSelector: UInt32 = 2

struct SMCError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

struct SMC {
    let conn: io_connect_t

    static func open() -> Result<SMC, SMCError> {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        if service == 0 {
            return .failure(SMCError(message: "IOServiceGetMatchingService(\"AppleSMC\") returned 0"))
        }
        var conn: io_connect_t = 0
        let kr = IOServiceOpen(service, mach_task_self_, 0, &conn)
        IOObjectRelease(service)
        if kr != kIOReturnSuccess {
            return .failure(SMCError(message: "IOServiceOpen failed: \(machErrorString(kr))"))
        }
        return .success(SMC(conn: conn))
    }

    func close() {
        IOServiceClose(conn)
    }

    func call(_ input: inout SMCKeyData_t) -> (kern_return_t, SMCKeyData_t) {
        var output = SMCKeyData_t()
        let size = MemoryLayout<SMCKeyData_t>.size
        var outSize = size
        let kr = withUnsafePointer(to: &input) { inPtr in
            withUnsafeMutablePointer(to: &output) { outPtr in
                IOConnectCallStructMethod(conn, kSMCUserClientSelector, inPtr, size, outPtr, &outSize)
            }
        }
        return (kr, output)
    }

    func openSession() -> kern_return_t {
        return IOConnectCallScalarMethod(conn, 0, nil, 0, nil, nil)
    }
}
