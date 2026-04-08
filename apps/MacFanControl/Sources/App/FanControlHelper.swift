import Foundation
import SharedModels
import SMCBridge

@MainActor
protocol FanControlHelping: AnyObject {
    var usesMockHardware: Bool { get }
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

    var usesMockHardware: Bool {
        runtime.sourceKind == .mock
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

@MainActor
enum FanControlHelperFactory {
    static func make(runtime: MacHardwareRuntime, logger: FanControlLogger) -> any FanControlHelping {
        let environment = ProcessInfo.processInfo.environment
        guard environment["MFC_USE_HELPER_PROCESS"] == "1" else {
            logger.info("Using direct in-process fan control helper.")
            return DirectFanControlHelper(runtime: runtime)
        }

        let client = HelperProcessClient(logger: logger)
        if client.connectIfPossible() {
            logger.info("Using external helper process for fan control.")
            return ProcessFanControlHelper(client: client)
        }

        logger.warning("Helper process unavailable. Falling back to direct helper.")
        return DirectFanControlHelper(runtime: runtime)
    }
}

@MainActor
final class ProcessFanControlHelper: FanControlHelping {
    private let client: HelperProcessClient

    init(client: HelperProcessClient) {
        self.client = client
    }

    var usesMockHardware: Bool {
        false
    }

    var sourceKindLabel: String {
        "helperProcess"
    }

    var lastErrorDescription: String? {
        client.lastErrorDescription
    }

    func loadDescriptor() -> MacModelDescriptor? {
        client.loadDescriptor()
    }

    func loadSnapshot() -> SensorSnapshot? {
        client.loadSnapshot()
    }

    func applyTargetRPM(_ rpm: Int) -> Bool {
        client.applyTargetRPM(rpm)
    }

    func revertAllFansToAuto() -> Bool {
        client.revertAllFansToAuto()
    }
}
