import Testing
import Foundation
@testable import embercap

@Test func fourCCPacksBigEndian() {
    #expect(fourCC("BCLM") == 0x42434C4D)
    #expect(fourCC("TB0T") == 0x5442_3054)
    #expect(fourCC("CH0B") == 0x4348_3042)
}

@Test func fourCCToStringIsInverse() {
    for key in ["BCLM", "TB0T", "CH0B", "BNum"] {
        #expect(fourCCToString(fourCC(key)) == key)
    }
}

@Test func padPadsOnRight() {
    #expect(pad("abc", 6) == "abc   ")
    #expect(pad("abcdef", 4) == "abcd")   // truncates
    #expect(pad("", 3) == "   ")
}

@Test func hexByteIsTwoCharsLowercase() {
    #expect(hexByte(0) == "00")
    #expect(hexByte(0xff) == "ff")
    #expect(hexByte(0x0a) == "0a")
}

@Test func machErrorStringContainsHex() {
    let s = machErrorString(0)
    #expect(s.contains("0x00000000"))
}
