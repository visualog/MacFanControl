import Foundation
import SharedModels
import SMCBridge

@MainActor
final class MacHardwareRuntime {
    enum SourceKind: String {
        case mock
        case intelSMC
    }

    let sourceKind: SourceKind
    let thermalService: ThermalHardwareService
    var lastHardwareError: String?

    init(sourceKind: SourceKind, thermalService: ThermalHardwareService) {
        self.sourceKind = sourceKind
        self.thermalService = thermalService
    }

    func loadDescriptor() -> MacModelDescriptor? {
        do {
            return try thermalService.loadDescriptor()
        } catch {
            lastHardwareError = error.localizedDescription
            return nil
        }
    }

    func loadSnapshot() -> SensorSnapshot? {
        do {
            return try thermalService.loadSnapshot()
        } catch {
            lastHardwareError = error.localizedDescription
            return nil
        }
    }

    func applyTargetRPM(_ rpm: Int) -> Bool {
        do {
            try thermalService.applyTargetRPM(rpm)
            lastHardwareError = nil
            return true
        } catch {
            lastHardwareError = error.localizedDescription
            return false
        }
    }

    func revertAllFansToAuto() -> Bool {
        do {
            try thermalService.revertAllFansToAuto()
            lastHardwareError = nil
            return true
        } catch {
            lastHardwareError = error.localizedDescription
            return false
        }
    }

    static func previewRuntime() -> MacHardwareRuntime {
        let controller = MockSMCController(
            snapshot: SensorSnapshot(
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
            ),
            descriptor: MacModelDescriptor(
                identifier: "MacBookPro16,1",
                fanCapabilities: [
                    .init(id: 0, minimumRPM: 1836, maximumRPM: 5500),
                    .init(id: 1, minimumRPM: 1836, maximumRPM: 5500),
                ]
            )
        )

        return MacHardwareRuntime(
            sourceKind: .mock,
            thermalService: ThermalHardwareService(controller: controller)
        )
    }

    static func defaultRuntime() -> MacHardwareRuntime {
        let environment = ProcessInfo.processInfo.environment
        if environment["MFC_USE_INTEL_SMC"] == "1" {
            return intelRuntime()
        }

        return previewRuntime()
    }

    static func intelRuntime() -> MacHardwareRuntime {
        let controller = IntelSMCController(transport: AppleSMCTransport())
        return MacHardwareRuntime(
            sourceKind: .intelSMC,
            thermalService: ThermalHardwareService(controller: controller)
        )
    }
}
