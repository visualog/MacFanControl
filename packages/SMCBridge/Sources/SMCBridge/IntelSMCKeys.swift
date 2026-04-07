import Foundation

public enum IntelSMCKey: String, CaseIterable, Sendable {
    case fan0CurrentRPM = "F0Ac"
    case fan1CurrentRPM = "F1Ac"
    case fan0MinimumRPM = "F0Mn"
    case fan1MinimumRPM = "F1Mn"
    case fan0MaximumRPM = "F0Mx"
    case fan1MaximumRPM = "F1Mx"
    case fan0TargetRPM = "F0Tg"
    case fan1TargetRPM = "F1Tg"
    case fanMode = "FS! "

    case cpuProximity = "TC0P"
    case gpuDiode = "TG0D"
    case palmRest = "Tp0P"
    case platformControllerHub = "TPCD"
}

public enum IntelSMCDataType: String, Sendable {
    case float = "flt "
    case fixedPoint78 = "fpe2"
    case signedTemperature = "sp78"
    case unsigned8 = "ui8 "
    case unsigned16 = "ui16"
    case bytes = "{fds"
}

public struct IntelSensorDefinition: Sendable, Hashable {
    public let key: IntelSMCKey
    public let displayName: String

    public init(key: IntelSMCKey, displayName: String) {
        self.key = key
        self.displayName = displayName
    }
}

public enum IntelMacModelProfiles {
    public static let macBookPro16_1Sensors: [IntelSensorDefinition] = [
        .init(key: .cpuProximity, displayName: "CPU Proximity"),
        .init(key: .gpuDiode, displayName: "GPU Diode"),
        .init(key: .palmRest, displayName: "Palm Rest"),
        .init(key: .platformControllerHub, displayName: "PCH"),
    ]
}
