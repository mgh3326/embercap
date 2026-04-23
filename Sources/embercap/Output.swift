import Foundation
import Darwin

func fourCC(_ s: String) -> UInt32 {
    precondition(s.utf8.count == 4, "SMC key must be exactly 4 ASCII chars: \(s)")
    let b = Array(s.utf8)
    return (UInt32(b[0]) << 24) | (UInt32(b[1]) << 16) | (UInt32(b[2]) << 8) | UInt32(b[3])
}

func fourCCToString(_ code: UInt32) -> String {
    let bytes: [UInt8] = [
        UInt8((code >> 24) & 0xff),
        UInt8((code >> 16) & 0xff),
        UInt8((code >> 8) & 0xff),
        UInt8(code & 0xff),
    ]
    return String(bytes: bytes, encoding: .ascii) ?? "????"
}

func pad(_ s: String, _ width: Int) -> String {
    if s.count >= width { return String(s.prefix(width)) }
    return s + String(repeating: " ", count: width - s.count)
}

func hexByte(_ b: UInt8) -> String {
    return String(format: "%02x", b)
}

func machErrorString(_ kr: Int32) -> String {
    let raw = mach_error_string(kr).map { String(cString: $0) } ?? "unknown"
    let hex = String(format: "0x%08x", UInt32(bitPattern: kr))
    return "\(raw) (\(hex))"
}
