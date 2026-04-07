import Foundation
import SharedModels

public struct FanCapability: Sendable, Hashable {
    public let id: Int
    public let minimumRPM: Int
    public let maximumRPM: Int

    public init(id: Int, minimumRPM: Int, maximumRPM: Int) {
        self.id = id
        self.minimumRPM = minimumRPM
        self.maximumRPM = maximumRPM
    }
}

public struct MacModelDescriptor: Sendable, Hashable {
    public let identifier: String
    public let fanCapabilities: [FanCapability]

    public init(identifier: String, fanCapabilities: [FanCapability]) {
        self.identifier = identifier
        self.fanCapabilities = fanCapabilities
    }
}

public protocol SMCControlling: Sendable {
    func readModelDescriptor() throws -> MacModelDescriptor
    func readSnapshot() throws -> SensorSnapshot
    func setFanRPM(_ rpm: Int, fanID: Int) throws
    func revertFanToAuto(fanID: Int) throws
}

public enum SMCBridgeError: Error, Sendable {
    case unsupportedPlatform
    case readFailed(String)
    case writeFailed(String)
    case invalidPayload(String)
    case notOpen
}

public final class MockSMCController: SMCControlling {
    private var snapshot: SensorSnapshot
    private let descriptor: MacModelDescriptor

    public init(snapshot: SensorSnapshot, descriptor: MacModelDescriptor) {
        self.snapshot = snapshot
        self.descriptor = descriptor
    }

    public func readModelDescriptor() throws -> MacModelDescriptor {
        descriptor
    }

    public func readSnapshot() throws -> SensorSnapshot {
        snapshot
    }

    public func setFanRPM(_ rpm: Int, fanID: Int) throws {
        snapshot = SensorSnapshot(
            timestamp: .now,
            temperatures: snapshot.temperatures,
            fans: snapshot.fans.map { fan in
                guard fan.id == fanID else { return fan }
                return FanReading(id: fan.id, currentRPM: rpm, targetRPM: rpm)
            },
            isExternalDisplayConnected: snapshot.isExternalDisplayConnected,
            isClamshellMode: snapshot.isClamshellMode
        )
    }

    public func revertFanToAuto(fanID: Int) throws {
        snapshot = SensorSnapshot(
            timestamp: .now,
            temperatures: snapshot.temperatures,
            fans: snapshot.fans.map { fan in
                guard fan.id == fanID else { return fan }
                return FanReading(id: fan.id, currentRPM: fan.currentRPM, targetRPM: nil)
            },
            isExternalDisplayConnected: snapshot.isExternalDisplayConnected,
            isClamshellMode: snapshot.isClamshellMode
        )
    }
}
