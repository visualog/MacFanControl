import Foundation
import SharedModels

public final class ThermalHardwareService: @unchecked Sendable {
    private let controller: any SMCControlling

    public init(controller: any SMCControlling) {
        self.controller = controller
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
    }

    public func revertAllFansToAuto() throws {
        try controller.revertFanToAuto(fanID: 0)
        try controller.revertFanToAuto(fanID: 1)
    }
}
