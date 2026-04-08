import Foundation
import SharedModels
import SMCBridge

private struct HelperServiceRuntime {
    let sourceLabel: String
    let thermalService: ThermalHardwareService

    static func `default`() -> HelperServiceRuntime {
        let environment = ProcessInfo.processInfo.environment
        if environment["MFC_USE_INTEL_SMC"] == "1" || environment["MFC_HELPER_USE_INTEL_SMC"] == "1" {
            return HelperServiceRuntime(
                sourceLabel: "intelSMC",
                thermalService: ThermalHardwareService(
                    controller: IntelSMCController(transport: AppleSMCTransport())
                )
            )
        }

        let controller = MockSMCController(
            snapshot: SensorSnapshot(
                timestamp: .now,
                temperatures: [
                    .init(name: "CPU Proximity", celsius: 73.0),
                    .init(name: "GPU Diode", celsius: 70.5),
                    .init(name: "Palm Rest", celsius: 31.2),
                ],
                fans: [
                    .init(id: 0, currentRPM: 2400, targetRPM: 2400),
                    .init(id: 1, currentRPM: 2380, targetRPM: 2400),
                ],
                isExternalDisplayConnected: false,
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

        return HelperServiceRuntime(
            sourceLabel: "mock",
            thermalService: ThermalHardwareService(controller: controller)
        )
    }

    func handle(_ command: HelperCommand) -> HelperResponse {
        do {
            switch command {
            case .ping:
                return .pong(sourceLabel)
            case .loadDescriptor:
                return .descriptor(try thermalService.loadDescriptor())
            case .loadSnapshot:
                return .snapshot(try thermalService.loadSnapshot())
            case .applyTargetRPM(let rpm):
                try thermalService.applyTargetRPM(rpm)
                return .ack
            case .revertAllFansToAuto:
                try thermalService.revertAllFansToAuto()
                return .ack
            }
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}

private let runtime = HelperServiceRuntime.default()

while let line = readLine() {
    guard let input = line.data(using: .utf8) else { continue }
    let response: HelperResponse
    do {
        let command = try HelperCodec.decode(HelperCommand.self, from: input)
        response = runtime.handle(command)
    } catch {
        response = .failure(error.localizedDescription)
    }

    do {
        let encoded = try HelperCodec.encodeLine(response)
        FileHandle.standardOutput.write(encoded)
    } catch {
        let message = "{\"kind\":\"failure\",\"message\":\"\(error.localizedDescription)\"}\n"
        FileHandle.standardOutput.write(Data(message.utf8))
    }
}
