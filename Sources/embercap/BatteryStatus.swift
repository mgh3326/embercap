import Foundation
import IOKit
import IOKit.ps

struct BatterySnapshot: Sendable, Equatable, Codable {
    let isPresent: Bool
    let isCharging: Bool?
    let isCharged: Bool?
    let externalConnected: Bool?
    let powerSourceState: String?
    let currentCapacityPercent: Int?
    let timeToFullMinutes: Int?
    let timeToEmptyMinutes: Int?
    let serial: String?
    let cycleCount: Int?
    let designCapacityMAh: Int?
    let maxCapacityMAh: Int?
    let currentCapacityMAh: Int?
    let temperatureCelsius: Double?
    let fullyCharged: Bool?
    let notChargingReason: Int?
}

enum BatteryStatusReader {
    static func collect() -> BatterySnapshot {
        let ips = readIOPS()
        let reg = readAppleSmartBattery()
        return BatterySnapshot(
            isPresent: ips.isPresent ?? reg.batteryInstalled ?? false,
            isCharging: ips.isCharging ?? reg.isCharging,
            isCharged: ips.isCharged,
            externalConnected: reg.externalConnected,
            powerSourceState: ips.powerSourceState,
            currentCapacityPercent: ips.currentCapacityPercent,
            timeToFullMinutes: ips.timeToFull,
            timeToEmptyMinutes: ips.timeToEmpty,
            serial: ips.serial ?? reg.serial,
            cycleCount: reg.cycleCount,
            designCapacityMAh: reg.designCapacity,
            maxCapacityMAh: reg.maxCapacity,
            currentCapacityMAh: reg.currentCapacity,
            temperatureCelsius: reg.temperature.map { Double($0) / 100.0 },
            fullyCharged: reg.fullyCharged,
            notChargingReason: reg.notChargingReason
        )
    }

    private struct IOPSFields {
        var isPresent: Bool?
        var isCharging: Bool?
        var isCharged: Bool?
        var powerSourceState: String?
        var currentCapacityPercent: Int?
        var timeToFull: Int?
        var timeToEmpty: Int?
        var serial: String?
    }

    private static func readIOPS() -> IOPSFields {
        var f = IOPSFields()
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
              let source = list.first,
              let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] else {
            return f
        }
        f.isPresent = desc["Is Present"] as? Bool
        f.isCharging = desc["Is Charging"] as? Bool
        f.isCharged = desc["Is Charged"] as? Bool
        f.powerSourceState = desc["Power Source State"] as? String
        f.currentCapacityPercent = desc["Current Capacity"] as? Int
        if let t = desc["Time to Full Charge"] as? Int, t > 0 { f.timeToFull = t }
        if let t = desc["Time to Empty"] as? Int, t > 0 { f.timeToEmpty = t }
        f.serial = desc["Hardware Serial Number"] as? String
        return f
    }

    private struct RegFields {
        var batteryInstalled: Bool?
        var isCharging: Bool?
        var externalConnected: Bool?
        var serial: String?
        var cycleCount: Int?
        var designCapacity: Int?
        var maxCapacity: Int?
        var currentCapacity: Int?
        var temperature: Int?
        var fullyCharged: Bool?
        var notChargingReason: Int?
    }

    private static func readAppleSmartBattery() -> RegFields {
        var f = RegFields()
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if service == 0 { return f }
        defer { IOObjectRelease(service) }
        var propsRef: Unmanaged<CFMutableDictionary>?
        let kr = IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0)
        guard kr == kIOReturnSuccess, let props = propsRef?.takeRetainedValue() as? [String: Any] else {
            return f
        }
        f.batteryInstalled = props["BatteryInstalled"] as? Bool
        f.isCharging = props["IsCharging"] as? Bool
        f.externalConnected = props["ExternalConnected"] as? Bool
        f.serial = props["Serial"] as? String
        f.cycleCount = props["CycleCount"] as? Int
        f.designCapacity = props["DesignCapacity"] as? Int
        f.maxCapacity = props["MaxCapacity"] as? Int
        f.currentCapacity = props["CurrentCapacity"] as? Int
        f.temperature = props["Temperature"] as? Int
        f.fullyCharged = props["FullyCharged"] as? Bool
        if let charger = props["ChargerData"] as? [String: Any] {
            f.notChargingReason = charger["NotChargingReason"] as? Int
        }
        return f
    }
}

func renderBatteryHuman(_ b: BatterySnapshot) -> String {
    var out = "== battery status ==\n"
    func line(_ label: String, _ v: Any?) {
        if let v = v { out += "  \(pad(label, 22)) \(v)\n" }
    }
    line("present", b.isPresent)
    line("power source state", b.powerSourceState)
    line("charging", b.isCharging)
    line("fully charged", b.fullyCharged)
    line("external connected", b.externalConnected)
    line("current %", b.currentCapacityPercent.map { "\($0)%" })
    line("design mAh", b.designCapacityMAh)
    line("max mAh", b.maxCapacityMAh)
    line("current mAh", b.currentCapacityMAh)
    line("cycle count", b.cycleCount)
    line("temperature", b.temperatureCelsius.map { String(format: "%.1f °C", $0) })
    line("time to full (min)", b.timeToFullMinutes)
    line("time to empty (min)", b.timeToEmptyMinutes)
    line("not charging reason", b.notChargingReason)
    line("serial", b.serial)
    return out
}
