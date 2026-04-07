import Foundation

public enum DeviceMode: String, Codable, Sendable {
    case systemAuto
    case profile
    case manualFixed
    case emergencyOverride
    case fallback
}

public enum ProfileKind: String, Codable, CaseIterable, Sendable {
    case quiet
    case balanced
    case performance
    case custom
}

public struct FanReading: Codable, Hashable, Sendable {
    public let id: Int
    public let currentRPM: Int
    public let targetRPM: Int?

    public init(id: Int, currentRPM: Int, targetRPM: Int? = nil) {
        self.id = id
        self.currentRPM = currentRPM
        self.targetRPM = targetRPM
    }
}

public struct TemperatureReading: Codable, Hashable, Sendable {
    public let name: String
    public let celsius: Double

    public init(name: String, celsius: Double) {
        self.name = name
        self.celsius = celsius
    }
}

public struct SensorSnapshot: Codable, Hashable, Sendable {
    public let timestamp: Date
    public let temperatures: [TemperatureReading]
    public let fans: [FanReading]
    public let isExternalDisplayConnected: Bool
    public let isClamshellMode: Bool

    public init(
        timestamp: Date,
        temperatures: [TemperatureReading],
        fans: [FanReading],
        isExternalDisplayConnected: Bool,
        isClamshellMode: Bool
    ) {
        self.timestamp = timestamp
        self.temperatures = temperatures
        self.fans = fans
        self.isExternalDisplayConnected = isExternalDisplayConnected
        self.isClamshellMode = isClamshellMode
    }

    public var highestTemperature: Double? {
        temperatures.map(\.celsius).max()
    }
}

public struct FanCurvePoint: Codable, Hashable, Sendable {
    public let temperatureCelsius: Double
    public let fanRPM: Int

    public init(temperatureCelsius: Double, fanRPM: Int) {
        self.temperatureCelsius = temperatureCelsius
        self.fanRPM = fanRPM
    }
}

public struct FanProfile: Codable, Hashable, Sendable {
    public let kind: ProfileKind
    public let name: String
    public let curve: [FanCurvePoint]

    public init(kind: ProfileKind, name: String, curve: [FanCurvePoint]) {
        self.kind = kind
        self.name = name
        self.curve = curve
    }
}

public struct SafetyStatus: Codable, Hashable, Sendable {
    public let isEmergencyOverrideActive: Bool
    public let reason: String

    public init(isEmergencyOverrideActive: Bool, reason: String) {
        self.isEmergencyOverrideActive = isEmergencyOverrideActive
        self.reason = reason
    }
}

public struct DeviceStatus: Codable, Hashable, Sendable {
    public let mode: DeviceMode
    public let activeProfile: ProfileKind?
    public let snapshot: SensorSnapshot
    public let safety: SafetyStatus

    public init(
        mode: DeviceMode,
        activeProfile: ProfileKind?,
        snapshot: SensorSnapshot,
        safety: SafetyStatus
    ) {
        self.mode = mode
        self.activeProfile = activeProfile
        self.snapshot = snapshot
        self.safety = safety
    }
}
