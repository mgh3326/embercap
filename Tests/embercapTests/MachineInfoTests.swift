import Testing
@testable import embercap

@Test func parseSIPEnabled() {
    #expect(parseSIPStatus("System Integrity Protection status: enabled.") == .enabled)
}

@Test func parseSIPDisabled() {
    #expect(parseSIPStatus("System Integrity Protection status: disabled.") == .disabled)
}

@Test func parseSIPUnknown() {
    #expect(parseSIPStatus("whatever") == .unknown)
}

@Test func parseSwVersProductAndBuild() {
    let sample = """
    ProductName:\t\tmacOS
    ProductVersion:\t\t26.4.1
    BuildVersion:\t\t25E253
    """
    let v = parseSwVers(sample)
    #expect(v.productName == "macOS")
    #expect(v.productVersion == "26.4.1")
    #expect(v.buildVersion == "25E253")
}
