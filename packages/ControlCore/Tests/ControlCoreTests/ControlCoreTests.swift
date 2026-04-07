import Testing
import SharedModels
@testable import ControlCore

@Test func entersEmergencyOverrideAtCriticalThreshold() {
    let engine = ControlEngine(
        limits: .init(minimumRPM: 2000, maximumRPM: 5500, emergencyTemperatureCelsius: 95)
    )

    let snapshot = SensorSnapshot(
        timestamp: .now,
        temperatures: [.init(name: "cpu", celsius: 96)],
        fans: [],
        isExternalDisplayConnected: false,
        isClamshellMode: false
    )

    let profile = FanProfile(
        kind: .balanced,
        name: "Balanced",
        curve: [.init(temperatureCelsius: 50, fanRPM: 2200)]
    )

    let decision = engine.decide(snapshot: snapshot, profile: profile, previousTargetRPM: nil)

    #expect(decision.status.isEmergencyOverrideActive)
    #expect(decision.command == .emergency(5500, reason: "Critical temperature"))
}

@Test func rateLimitsRequestedRPM() {
    let engine = ControlEngine(
        limits: .init(
            minimumRPM: 2000,
            maximumRPM: 5500,
            emergencyTemperatureCelsius: 95,
            maxStepChangeRPM: 300
        )
    )

    let snapshot = SensorSnapshot(
        timestamp: .now,
        temperatures: [.init(name: "cpu", celsius: 80)],
        fans: [],
        isExternalDisplayConnected: false,
        isClamshellMode: false
    )

    let profile = FanProfile(
        kind: .performance,
        name: "Performance",
        curve: [
            .init(temperatureCelsius: 60, fanRPM: 2500),
            .init(temperatureCelsius: 90, fanRPM: 5000),
        ]
    )

    let decision = engine.decide(snapshot: snapshot, profile: profile, previousTargetRPM: 2600)

    #expect(decision.command == .setRPM(2900, reason: "Profile performance"))
}
