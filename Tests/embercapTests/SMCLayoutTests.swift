import Testing
@testable import embercap

@Test func smcKeyDataTotalSizeMatchesCLayout() {
    #expect(MemoryLayout<SMCKeyData_t>.size == 76)
}

@Test func smcKeyDataFieldOffsetsMatchCLayout() {
    #expect(MemoryLayout<SMCKeyData_t>.offset(of: \.key) == 0)
    #expect(MemoryLayout<SMCKeyData_t>.offset(of: \.vers) == 4)
    #expect(MemoryLayout<SMCKeyData_t>.offset(of: \.pLimitData) == 12)
    #expect(MemoryLayout<SMCKeyData_t>.offset(of: \.keyInfo) == 28)
    #expect(MemoryLayout<SMCKeyData_t>.offset(of: \.result) == 37)
    #expect(MemoryLayout<SMCKeyData_t>.offset(of: \.status) == 38)
    #expect(MemoryLayout<SMCKeyData_t>.offset(of: \.data8) == 39)
    #expect(MemoryLayout<SMCKeyData_t>.offset(of: \.data32) == 40)
}
