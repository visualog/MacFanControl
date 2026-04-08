import Foundation
import SharedModels
import SMCBridge

@MainActor
protocol FanControlHelping: AnyObject {
    var sourceKindLabel: String { get }
    var lastErrorDescription: String? { get }
    func loadDescriptor() -> MacModelDescriptor?
    func loadSnapshot() -> SensorSnapshot?
    func applyTargetRPM(_ rpm: Int) -> Bool
    func revertAllFansToAuto() -> Bool
}

@MainActor
final class DirectFanControlHelper: FanControlHelping {
    private let runtime: MacHardwareRuntime

    init(runtime: MacHardwareRuntime) {
        self.runtime = runtime
    }

    var sourceKindLabel: String {
        runtime.sourceKind.rawValue
    }

    var lastErrorDescription: String? {
        runtime.lastHardwareError
    }

    func loadDescriptor() -> MacModelDescriptor? {
        runtime.loadDescriptor()
    }

    func loadSnapshot() -> SensorSnapshot? {
        runtime.loadSnapshot()
    }

    func applyTargetRPM(_ rpm: Int) -> Bool {
        runtime.applyTargetRPM(rpm)
    }

    func revertAllFansToAuto() -> Bool {
        runtime.revertAllFansToAuto()
    }
}
