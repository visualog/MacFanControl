import Foundation
import SharedModels

public enum PairingState: String, Codable, Sendable {
    case pending
    case paired
    case rejected
    case expired
}

public struct PairingStartResponse: Codable, Sendable {
    public let sessionID: UUID
    public let code: String
    public let expiresAt: Date

    public init(sessionID: UUID, code: String, expiresAt: Date) {
        self.sessionID = sessionID
        self.code = code
        self.expiresAt = expiresAt
    }
}

public struct PairingConfirmRequest: Codable, Sendable {
    public let sessionID: UUID
    public let code: String
    public let deviceName: String

    public init(sessionID: UUID, code: String, deviceName: String) {
        self.sessionID = sessionID
        self.code = code
        self.deviceName = deviceName
    }
}

public struct PairingConfirmResponse: Codable, Sendable {
    public let state: PairingState
    public let token: String?

    public init(state: PairingState, token: String?) {
        self.state = state
        self.token = token
    }
}

public struct ApplyProfileRequest: Codable, Sendable {
    public let profile: ProfileKind

    public init(profile: ProfileKind) {
        self.profile = profile
    }
}

public struct ApplyCurveRequest: Codable, Sendable {
    public let profileName: String
    public let points: [FanCurvePoint]

    public init(profileName: String, points: [FanCurvePoint]) {
        self.profileName = profileName
        self.points = points
    }
}

public struct ValidationResponse: Codable, Sendable {
    public let accepted: Bool
    public let reason: String

    public init(accepted: Bool, reason: String) {
        self.accepted = accepted
        self.reason = reason
    }
}

public enum RemoteCommand: Codable, Sendable {
    case fetchStatus
    case fetchProfiles
    case applyProfile(ApplyProfileRequest)
    case validateCurve(ApplyCurveRequest)
}

public enum RemoteResponse: Codable, Sendable {
    case status(DeviceStatus)
    case profiles([FanProfile])
    case validation(ValidationResponse)
    case error(String)
}

public enum TelemetryEvent: Codable, Sendable {
    case status(DeviceStatus)
    case warning(String)
    case pairedDeviceChanged(String)
}

public enum LocalTransport {
    public static let bonjourServiceType = "_mfc-control._tcp"
    public static let defaultPort = 48_484
    public static let newline = "\n"
}

public enum RemoteCodec {
    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public static func encodeLine<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value) + Data(LocalTransport.newline.utf8)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder.decode(T.self, from: data)
    }
}
