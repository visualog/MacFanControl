import Foundation
import Observation
import ControlCore
import RemoteProtocol
import SharedModels
import SMCBridge

@MainActor
@Observable
final class MacDashboardController {
    let modelDescriptor: MacModelDescriptor
    let remoteServer: RemoteControlServer
    let hardwareRuntime: MacHardwareRuntime
    let helper: any FanControlHelping
    let logger: FanControlLogger

    var availableProfiles: [FanProfile]
    var activeProfile: FanProfile
    var localNetworkServer: MacLocalNetworkServer?
    var mode: DeviceMode
    var snapshot: SensorSnapshot
    var safetyStatus: SafetyStatus
    var lastCommandSummary: String
    var controlLoopSummary: String
    var hardwareStatusSummary: String
    var cadenceLimitSeconds: TimeInterval
    var lastControlTickAt: Date?
    var temperatureSamples: [Double]

    private var controlTask: Task<Void, Never>?

    init(
        modelDescriptor: MacModelDescriptor,
        availableProfiles: [FanProfile],
        activeProfile: FanProfile,
        remoteServer: RemoteControlServer,
        hardwareRuntime: MacHardwareRuntime,
        helper: any FanControlHelping,
        logger: FanControlLogger,
        mode: DeviceMode,
        snapshot: SensorSnapshot,
        safetyStatus: SafetyStatus,
        lastCommandSummary: String,
        controlLoopSummary: String,
        hardwareStatusSummary: String,
        cadenceLimitSeconds: TimeInterval = 3
    ) {
        self.modelDescriptor = modelDescriptor
        self.availableProfiles = availableProfiles
        self.activeProfile = activeProfile
        self.remoteServer = remoteServer
        self.hardwareRuntime = hardwareRuntime
        self.helper = helper
        self.logger = logger
        self.mode = mode
        self.snapshot = snapshot
        self.safetyStatus = safetyStatus
        self.lastCommandSummary = lastCommandSummary
        self.controlLoopSummary = controlLoopSummary
        self.hardwareStatusSummary = hardwareStatusSummary
        self.cadenceLimitSeconds = cadenceLimitSeconds
        self.temperatureSamples = []
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
        logger.info("Remote services started.")
    }

    func refreshFromHardwareIfAvailable() {
        guard hardwareRuntime.sourceKind == .intelSMC else {
            hardwareStatusSummary = "Running in mock hardware mode."
            logger.info("Using mock hardware runtime.")
            return
        }

        if let latestSnapshot = helper.loadSnapshot() {
            snapshot = latestSnapshot
            hardwareStatusSummary = "Intel SMC snapshot read succeeded at \(latestSnapshot.timestamp.formatted())"
            logger.info("Initial Intel SMC snapshot read succeeded.")
        }
        if let latestDescriptor = helper.loadDescriptor() {
            if latestDescriptor.identifier != modelDescriptor.identifier {
                lastCommandSummary = "Hardware descriptor differs from preview model: \(latestDescriptor.identifier)"
                logger.warning(lastCommandSummary)
            }
        }
        if let lastHardwareError = helper.lastErrorDescription {
            hardwareStatusSummary = "Intel SMC runtime error: \(lastHardwareError)"
            logger.error(hardwareStatusSummary)
        }
    }

    func startControlLoop() {
        guard controlTask == nil else { return }

        controlTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                self.runControlTick()
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
            },
            validateCurve: { [weak self] request in
                self?.validateCurveRequest(request) ?? ValidationResponse(
                    accepted: false,
                    reason: "Mac controller is unavailable."
                )
            }
        )
    }

    func runControlTick() {
        let now = Date()
        if let lastControlTickAt, now.timeIntervalSince(lastControlTickAt) < cadenceLimitSeconds {
            controlLoopSummary = "Skipped control tick to preserve cadence limit."
            return
        }
        lastControlTickAt = now

        guard let latestSnapshot = helper.loadSnapshot() else {
            mode = .fallback
            safetyStatus = SafetyStatus(
                isEmergencyOverrideActive: false,
                reason: helper.lastErrorDescription ?? "snapshot unavailable"
            )
            controlLoopSummary = "Snapshot read failed. Reverting toward safe fallback."
            hardwareStatusSummary = "Latest hardware read failed."
            logger.error(controlLoopSummary)
            _ = helper.revertAllFansToAuto()
            publishPreviewTelemetry()
            return
        }

        let filteredSnapshot = smoothedSnapshot(from: latestSnapshot)
        snapshot = filteredSnapshot

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
            snapshot: filteredSnapshot,
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

        let validation = validate(profile: profile)
        guard validation.accepted else { return validation }

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
        logger.info("Profile \(profile.kind.rawValue) accepted and queued.")
        publishPreviewTelemetry()

        return ValidationResponse(
            accepted: true,
            reason: "\(profile.name) applied on the Mac and republished to paired clients."
        )
    }

    func validateCurveRequest(_ request: ApplyCurveRequest) -> ValidationResponse {
        let profile = FanProfile(kind: .custom, name: request.profileName, curve: request.points)
        return validate(profile: profile)
    }

    private func apply(decision: ControlDecision) {
        safetyStatus = decision.status

        switch decision.command {
        case .keepCurrent(let reason):
            controlLoopSummary = reason
            logger.info(reason)
        case .setRPM(let rpm, let reason):
            let applied = helper.applyTargetRPM(rpm)
            mode = .profile
            controlLoopSummary = applied
                ? "Applied \(rpm) RPM. \(reason)"
                : "Failed to apply \(rpm) RPM. \(helper.lastErrorDescription ?? reason)"
            hardwareStatusSummary = applied ? "Hardware apply succeeded." : "Hardware apply failed."
            if applied {
                logger.info(controlLoopSummary)
            } else {
                logger.error(controlLoopSummary)
                failSafe(reason: "Fan write verification failed.")
            }
        case .revertToAuto(let reason):
            let reverted = helper.revertAllFansToAuto()
            mode = .systemAuto
            controlLoopSummary = reverted
                ? "Returned fans to automatic control. \(reason)"
                : "Failed to return fans to auto. \(helper.lastErrorDescription ?? reason)"
            hardwareStatusSummary = reverted ? "Hardware auto mode restore succeeded." : "Hardware auto mode restore failed."
            if reverted {
                logger.warning(controlLoopSummary)
            } else {
                logger.error(controlLoopSummary)
            }
        case .emergency(let rpm, let reason):
            let applied = helper.applyTargetRPM(rpm)
            mode = .emergencyOverride
            controlLoopSummary = applied
                ? "Emergency override at \(rpm) RPM. \(reason)"
                : "Emergency override failed. \(helper.lastErrorDescription ?? reason)"
            hardwareStatusSummary = applied ? "Emergency hardware apply succeeded." : "Emergency hardware apply failed."
            if applied {
                logger.warning(controlLoopSummary)
            } else {
                logger.error(controlLoopSummary)
                failSafe(reason: "Emergency fan apply failed.")
            }
        }
    }

    private func failSafe(reason: String) {
        mode = .fallback
        safetyStatus = SafetyStatus(isEmergencyOverrideActive: false, reason: reason)
        controlLoopSummary = "Fail-safe engaged. \(reason)"
        hardwareStatusSummary = helper.lastErrorDescription ?? reason
        _ = helper.revertAllFansToAuto()
        logger.error(controlLoopSummary)
    }

    private func validate(profile: FanProfile) -> ValidationResponse {
        guard !profile.curve.isEmpty else {
            return ValidationResponse(accepted: false, reason: "Profile curve cannot be empty.")
        }

        let minimumRPM = modelDescriptor.fanCapabilities.map(\.minimumRPM).min() ?? 1800
        let maximumRPM = modelDescriptor.fanCapabilities.map(\.maximumRPM).max() ?? 5500
        let sorted = profile.curve.sorted { $0.temperatureCelsius < $1.temperatureCelsius }

        guard sorted.count == profile.curve.count else {
            return ValidationResponse(accepted: false, reason: "Curve points must be sortable.")
        }

        for (left, right) in zip(sorted, sorted.dropFirst()) {
            guard right.temperatureCelsius > left.temperatureCelsius else {
                return ValidationResponse(accepted: false, reason: "Curve temperatures must strictly increase.")
            }
        }

        let allWithinBounds = sorted.allSatisfy { point in
            point.fanRPM >= minimumRPM && point.fanRPM <= maximumRPM
        }

        guard allWithinBounds else {
            return ValidationResponse(
                accepted: false,
                reason: "Curve RPM values must stay between \(minimumRPM) and \(maximumRPM)."
            )
        }

        return ValidationResponse(accepted: true, reason: "\(profile.name) passed safety validation.")
    }

    private func smoothedSnapshot(from snapshot: SensorSnapshot) -> SensorSnapshot {
        guard let hottest = snapshot.highestTemperature else { return snapshot }

        temperatureSamples.append(hottest)
        if temperatureSamples.count > 5 {
            temperatureSamples.removeFirst(temperatureSamples.count - 5)
        }

        let average = temperatureSamples.reduce(0, +) / Double(temperatureSamples.count)
        guard let index = snapshot.temperatures.indices.max(by: {
            snapshot.temperatures[$0].celsius < snapshot.temperatures[$1].celsius
        }) else {
            return snapshot
        }

        var temperatures = snapshot.temperatures
        let hottestReading = temperatures[index]
        temperatures[index] = TemperatureReading(name: hottestReading.name, celsius: average)

        return SensorSnapshot(
            timestamp: snapshot.timestamp,
            temperatures: temperatures,
            fans: snapshot.fans,
            isExternalDisplayConnected: snapshot.isExternalDisplayConnected,
            isClamshellMode: snapshot.isClamshellMode
        )
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
        let logger = FanControlLogger()
        let controller = MacDashboardController(
            modelDescriptor: modelDescriptor,
            availableProfiles: [quiet, profile, performance, custom],
            activeProfile: profile,
            remoteServer: .preview,
            hardwareRuntime: hardwareRuntime,
            helper: DirectFanControlHelper(runtime: hardwareRuntime),
            logger: logger,
            mode: .profile,
            snapshot: snapshot,
            safetyStatus: safety,
            lastCommandSummary: "Balanced profile requests 3000 RPM from CPU/GPU thermal curve.",
            controlLoopSummary: "Control loop idle.",
            hardwareStatusSummary: "Hardware runtime not sampled yet."
        )
        controller.bindLocalNetworkServer()
        return controller
    }
}
