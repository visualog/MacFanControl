import Foundation
import SharedModels

public struct ModelLimits: Sendable, Hashable {
    public let minimumRPM: Int
    public let maximumRPM: Int
    public let emergencyTemperatureCelsius: Double
    public let maxStepChangeRPM: Int

    public init(
        minimumRPM: Int,
        maximumRPM: Int,
        emergencyTemperatureCelsius: Double,
        maxStepChangeRPM: Int = 400
    ) {
        self.minimumRPM = minimumRPM
        self.maximumRPM = maximumRPM
        self.emergencyTemperatureCelsius = emergencyTemperatureCelsius
        self.maxStepChangeRPM = maxStepChangeRPM
    }
}

public enum FanCommand: Sendable, Equatable {
    case keepCurrent(reason: String)
    case setRPM(Int, reason: String)
    case revertToAuto(reason: String)
    case emergency(Int, reason: String)
}

public struct ControlDecision: Sendable, Equatable {
    public let command: FanCommand
    public let status: SafetyStatus

    public init(command: FanCommand, status: SafetyStatus) {
        self.command = command
        self.status = status
    }
}

public struct ThermalFilter: Sendable {
    public init() {}

    public func filteredTemperature(from snapshot: SensorSnapshot) -> Double? {
        snapshot.highestTemperature
    }
}

public struct CurveResolver: Sendable {
    public init() {}

    public func resolveRPM(for temperature: Double, profile: FanProfile) -> Int? {
        let points = profile.curve.sorted { $0.temperatureCelsius < $1.temperatureCelsius }
        guard let first = points.first else { return nil }
        if temperature <= first.temperatureCelsius { return first.fanRPM }

        for (left, right) in zip(points, points.dropFirst()) {
            guard temperature <= right.temperatureCelsius else { continue }
            let span = right.temperatureCelsius - left.temperatureCelsius
            guard span > 0 else { return right.fanRPM }
            let progress = (temperature - left.temperatureCelsius) / span
            let delta = Double(right.fanRPM - left.fanRPM)
            return Int(Double(left.fanRPM) + delta * progress)
        }

        return points.last?.fanRPM
    }
}

public struct RPMRateLimiter: Sendable {
    public init() {}

    public func apply(previousRPM: Int?, requestedRPM: Int, maxStepChangeRPM: Int) -> Int {
        guard let previousRPM else { return requestedRPM }
        let delta = requestedRPM - previousRPM

        if abs(delta) <= maxStepChangeRPM {
            return requestedRPM
        }

        return previousRPM + (delta > 0 ? maxStepChangeRPM : -maxStepChangeRPM)
    }
}

public struct ControlEngine: Sendable {
    public let limits: ModelLimits
    public let thermalFilter: ThermalFilter
    public let curveResolver: CurveResolver
    public let rateLimiter: RPMRateLimiter

    public init(
        limits: ModelLimits,
        thermalFilter: ThermalFilter = .init(),
        curveResolver: CurveResolver = .init(),
        rateLimiter: RPMRateLimiter = .init()
    ) {
        self.limits = limits
        self.thermalFilter = thermalFilter
        self.curveResolver = curveResolver
        self.rateLimiter = rateLimiter
    }

    public func decide(
        snapshot: SensorSnapshot,
        profile: FanProfile,
        previousTargetRPM: Int?
    ) -> ControlDecision {
        guard let hottest = thermalFilter.filteredTemperature(from: snapshot) else {
            return .init(
                command: .revertToAuto(reason: "No valid temperature data"),
                status: .init(isEmergencyOverrideActive: false, reason: "sensor read failed")
            )
        }

        if hottest >= limits.emergencyTemperatureCelsius {
            return .init(
                command: .emergency(limits.maximumRPM, reason: "Critical temperature"),
                status: .init(isEmergencyOverrideActive: true, reason: "critical temperature")
            )
        }

        guard let rawRPM = curveResolver.resolveRPM(for: hottest, profile: profile) else {
            return .init(
                command: .revertToAuto(reason: "Profile curve is empty"),
                status: .init(isEmergencyOverrideActive: false, reason: "invalid profile curve")
            )
        }

        let bounded = max(limits.minimumRPM, min(limits.maximumRPM, rawRPM))
        let smoothed = rateLimiter.apply(
            previousRPM: previousTargetRPM,
            requestedRPM: bounded,
            maxStepChangeRPM: limits.maxStepChangeRPM
        )

        return .init(
            command: .setRPM(smoothed, reason: "Profile \(profile.kind.rawValue)"),
            status: .init(isEmergencyOverrideActive: false, reason: "profile applied")
        )
    }
}
