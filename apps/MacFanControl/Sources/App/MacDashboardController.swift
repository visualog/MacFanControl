import Foundation
import Observation
import ControlCore
import SharedModels
import SMCBridge

@Observable
final class MacDashboardController {
    let modelDescriptor: MacModelDescriptor
    let remoteServer: RemoteControlServer
    let hardwareRuntime: MacHardwareRuntime

    var availableProfiles: [FanProfile]
    var activeProfile: FanProfile
    var localNetworkServer: MacLocalNetworkServer?
    var mode: DeviceMode
    var snapshot: SensorSnapshot
    var safetyStatus: SafetyStatus
    var lastCommandSummary: String
    var controlLoopSummary: String

    private var controlTask: Task<Void, Never>?

    init(
        modelDescriptor: MacModelDescriptor,
        availableProfiles: [FanProfile],
        activeProfile: FanProfile,
        remoteServer: RemoteControlServer,
        hardwareRuntime: MacHardwareRuntime,
        mode: DeviceMode,
        snapshot: SensorSnapshot,
        safetyStatus: SafetyStatus,
        lastCommandSummary: String,
        controlLoopSummary: String
    ) {
        self.modelDescriptor = modelDescriptor
        self.availableProfiles = availableProfiles
        self.activeProfile = activeProfile
        self.remoteServer = remoteServer
        self.hardwareRuntime = hardwareRuntime
        self.mode = mode
        self.snapshot = snapshot
        self.safetyStatus = safetyStatus
        self.lastCommandSummary = lastCommandSummary
        self.controlLoopSummary = controlLoopSummary
    }

    var deviceStatus: DeviceStatus {
        DeviceStatus(
            mode: mode,
            activeProfile: activeProfile.kind,
            snapshot: snapshot,
            safety: safetyStatus
        )
    }

    func publishPreviewTelemetry() {
        let status = deviceStatus
        remoteServer.publish(status: status)
        localNetworkServer?.publish(status)
    }

    func startRemoteServices() {
        localNetworkServer?.start()
    }

    func refreshFromHardwareIfAvailable() {
        guard hardwareRuntime.sourceKind == .intelSMC else { return }

        if let latestSnapshot = hardwareRuntime.loadSnapshot() {
            snapshot = latestSnapshot
        }
        if let latestDescriptor = hardwareRuntime.loadDescriptor() {
            if latestDescriptor.identifier != modelDescriptor.identifier {
                lastCommandSummary = "Hardware descriptor differs from preview model: \(latestDescriptor.identifier)"
            }
        }
    }

    func startControlLoop() {
        guard controlTask == nil else { return }

        controlTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.runControlTick()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func stopControlLoop() {
        controlTask?.cancel()
        controlTask = nil
    }

    func bindLocalNetworkServer() {
        localNetworkServer = MacLocalNetworkServer(
            listenPort: LocalTransport.defaultPort,
            makeStatus: { [weak self] in
                self?.deviceStatus ?? Self.fallbackStatus
            },
            makeProfiles: { [weak self] in
                self?.availableProfiles ?? []
            },
            applyProfile: { [weak self] profile in
                self?.applyProfile(profile) ?? ValidationResponse(
                    accepted: false,
                    reason: "Mac controller is unavailable."
                )
            }
        )
    }

    func runControlTick() {
        guard let latestSnapshot = hardwareRuntime.loadSnapshot() else {
            mode = .fallback
            safetyStatus = SafetyStatus(
                isEmergencyOverrideActive: false,
                reason: hardwareRuntime.lastHardwareError ?? "snapshot unavailable"
            )
            controlLoopSummary = "Snapshot read failed. Reverting toward safe fallback."
            _ = hardwareRuntime.revertAllFansToAuto()
            publishPreviewTelemetry()
            return
        }

        snapshot = latestSnapshot

        let fanCapabilities = modelDescriptor.fanCapabilities
        let minimumRPM = fanCapabilities.map(\.minimumRPM).min() ?? 1800
        let maximumRPM = fanCapabilities.map(\.maximumRPM).max() ?? 5500
        let previousTarget = snapshot.fans.compactMap(\.targetRPM).max()

        let engine = ControlEngine(
            limits: .init(
                minimumRPM: minimumRPM,
                maximumRPM: maximumRPM,
                emergencyTemperatureCelsius: 95
            )
        )

        let decision = engine.decide(
            snapshot: latestSnapshot,
            profile: activeProfile,
            previousTargetRPM: previousTarget
        )

        apply(decision: decision)
        publishPreviewTelemetry()
    }

    func applyProfile(_ kind: ProfileKind) -> ValidationResponse {
        guard let profile = availableProfiles.first(where: { $0.kind == kind }) else {
            return ValidationResponse(
                accepted: false,
                reason: "Requested profile is not available on this Mac."
            )
        }

        activeProfile = profile
        mode = .profile
        safetyStatus = SafetyStatus(
            isEmergencyOverrideActive: false,
            reason: "profile \(kind.rawValue) applied"
        )

        let targetRPM = profile.curve.last?.fanRPM
        snapshot = SensorSnapshot(
            timestamp: .now,
            temperatures: snapshot.temperatures,
            fans: snapshot.fans.map { fan in
                FanReading(id: fan.id, currentRPM: fan.currentRPM, targetRPM: targetRPM)
            },
            isExternalDisplayConnected: snapshot.isExternalDisplayConnected,
            isClamshellMode: snapshot.isClamshellMode
        )
        lastCommandSummary = "\(profile.name) profile accepted from remote client and queued for thermal control."
        controlLoopSummary = "\(profile.name) profile selected. Awaiting next control tick."
        publishPreviewTelemetry()

        return ValidationResponse(
            accepted: true,
            reason: "\(profile.name) applied on the Mac and republished to paired clients."
        )
    }

    private func apply(decision: ControlDecision) {
        safetyStatus = decision.status

        switch decision.command {
        case .keepCurrent(let reason):
            controlLoopSummary = reason
        case .setRPM(let rpm, let reason):
            let applied = hardwareRuntime.applyTargetRPM(rpm)
            mode = .profile
            controlLoopSummary = applied
                ? "Applied \(rpm) RPM. \(reason)"
                : "Failed to apply \(rpm) RPM. \(hardwareRuntime.lastHardwareError ?? reason)"
        case .revertToAuto(let reason):
            let reverted = hardwareRuntime.revertAllFansToAuto()
            mode = .systemAuto
            controlLoopSummary = reverted
                ? "Returned fans to automatic control. \(reason)"
                : "Failed to return fans to auto. \(hardwareRuntime.lastHardwareError ?? reason)"
        case .emergency(let rpm, let reason):
            let applied = hardwareRuntime.applyTargetRPM(rpm)
            mode = .emergencyOverride
            controlLoopSummary = applied
                ? "Emergency override at \(rpm) RPM. \(reason)"
                : "Emergency override failed. \(hardwareRuntime.lastHardwareError ?? reason)"
        }
    }

    private static var fallbackStatus: DeviceStatus {
        DeviceStatus(
            mode: .fallback,
            activeProfile: nil,
            snapshot: SensorSnapshot(
                timestamp: .now,
                temperatures: [],
                fans: [],
                isExternalDisplayConnected: false,
                isClamshellMode: false
            ),
            safety: SafetyStatus(
                isEmergencyOverrideActive: false,
                reason: "controller unavailable"
            )
        )
    }
}

extension MacDashboardController {
    static var preview: MacDashboardController {
        let modelDescriptor = MacModelDescriptor(
            identifier: "MacBookPro16,1",
            fanCapabilities: [
                .init(id: 0, minimumRPM: 1836, maximumRPM: 5500),
                .init(id: 1, minimumRPM: 1836, maximumRPM: 5500),
            ]
        )

        let profile = FanProfile(
            kind: .balanced,
            name: "Balanced",
            curve: [
                .init(temperatureCelsius: 45, fanRPM: 1900),
                .init(temperatureCelsius: 65, fanRPM: 2600),
                .init(temperatureCelsius: 82, fanRPM: 3800),
                .init(temperatureCelsius: 92, fanRPM: 5200),
            ]
        )
        let quiet = FanProfile(
            kind: .quiet,
            name: "Quiet",
            curve: [
                .init(temperatureCelsius: 45, fanRPM: 1836),
                .init(temperatureCelsius: 70, fanRPM: 2200),
                .init(temperatureCelsius: 85, fanRPM: 3200),
            ]
        )
        let performance = FanProfile(
            kind: .performance,
            name: "Performance",
            curve: [
                .init(temperatureCelsius: 45, fanRPM: 2200),
                .init(temperatureCelsius: 65, fanRPM: 3200),
                .init(temperatureCelsius: 80, fanRPM: 4300),
                .init(temperatureCelsius: 92, fanRPM: 5500),
            ]
        )
        let custom = FanProfile(
            kind: .custom,
            name: "Custom Curve",
            curve: [
                .init(temperatureCelsius: 45, fanRPM: 2000),
                .init(temperatureCelsius: 68, fanRPM: 2800),
                .init(temperatureCelsius: 86, fanRPM: 4100),
                .init(temperatureCelsius: 92, fanRPM: 5200),
            ]
        )

        let snapshot = SensorSnapshot(
            timestamp: .now,
            temperatures: [
                .init(name: "CPU Proximity", celsius: 78.4),
                .init(name: "GPU Diode", celsius: 74.8),
                .init(name: "Palm Rest", celsius: 33.1),
            ],
            fans: [
                .init(id: 0, currentRPM: 2890, targetRPM: 3000),
                .init(id: 1, currentRPM: 2845, targetRPM: 3000),
            ],
            isExternalDisplayConnected: true,
            isClamshellMode: false
        )

        let safety = SafetyStatus(isEmergencyOverrideActive: false, reason: "profile applied")
        let hardwareRuntime = MacHardwareRuntime.defaultRuntime()
        let controller = MacDashboardController(
            modelDescriptor: modelDescriptor,
            availableProfiles: [quiet, profile, performance, custom],
            activeProfile: profile,
            remoteServer: .preview,
            hardwareRuntime: hardwareRuntime,
            mode: .profile,
            snapshot: snapshot,
            safetyStatus: safety,
            lastCommandSummary: "Balanced profile requests 3000 RPM from CPU/GPU thermal curve.",
            controlLoopSummary: "Control loop idle."
        )
        controller.bindLocalNetworkServer()
        return controller
    }
}
