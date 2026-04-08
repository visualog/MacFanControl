import Foundation
import SharedModels

public final class ThermalHardwareService: @unchecked Sendable {
    private let controller: any SMCControlling
    private let verificationToleranceRPM: Int

    public init(
        controller: any SMCControlling,
        verificationToleranceRPM: Int = 1500
    ) {
        self.controller = controller
        self.verificationToleranceRPM = verificationToleranceRPM
    }

    public func loadDescriptor() throws -> MacModelDescriptor {
        try controller.readModelDescriptor()
    }

    public func loadSnapshot() throws -> SensorSnapshot {
        try controller.readSnapshot()
    }

    public func applyTargetRPM(_ rpm: Int) throws {
        try controller.setFanRPM(rpm, fanID: 0)
        try controller.setFanRPM(rpm, fanID: 1)
        try verifyPostWrite(targetRPM: rpm)
    }

    public func revertAllFansToAuto() throws {
        try controller.revertFanToAuto(fanID: 0)
        try controller.revertFanToAuto(fanID: 1)
    }

    private func verifyPostWrite(targetRPM: Int) throws {
        let snapshot = try controller.readSnapshot()
        let allValid = snapshot.fans.allSatisfy { fan in
            if let targetRPMReadback = fan.targetRPM {
                return abs(targetRPMReadback - targetRPM) <= verificationToleranceRPM
            }

            return abs(fan.currentRPM - targetRPM) <= verificationToleranceRPM
        }

        guard allValid else {
            throw SMCBridgeError.writeFailed("Post-write fan verification failed")
        }
    }
}
