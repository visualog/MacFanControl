import Foundation
import SharedModels
import SMCBridge

enum HelperCommand: Codable, Sendable {
    case ping
    case loadDescriptor
    case loadSnapshot
    case applyTargetRPM(Int)
    case revertAllFansToAuto

    private enum CodingKeys: String, CodingKey {
        case kind
        case rpm
    }

    private enum Kind: String, Codable {
        case ping
        case loadDescriptor
        case loadSnapshot
        case applyTargetRPM
        case revertAllFansToAuto
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .ping:
            self = .ping
        case .loadDescriptor:
            self = .loadDescriptor
        case .loadSnapshot:
            self = .loadSnapshot
        case .applyTargetRPM:
            self = .applyTargetRPM(try container.decode(Int.self, forKey: .rpm))
        case .revertAllFansToAuto:
            self = .revertAllFansToAuto
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .ping:
            try container.encode(Kind.ping, forKey: .kind)
        case .loadDescriptor:
            try container.encode(Kind.loadDescriptor, forKey: .kind)
        case .loadSnapshot:
            try container.encode(Kind.loadSnapshot, forKey: .kind)
        case .applyTargetRPM(let rpm):
            try container.encode(Kind.applyTargetRPM, forKey: .kind)
            try container.encode(rpm, forKey: .rpm)
        case .revertAllFansToAuto:
            try container.encode(Kind.revertAllFansToAuto, forKey: .kind)
        }
    }
}

enum HelperResponse: Codable, Sendable {
    case ack
    case descriptor(MacModelDescriptor)
    case snapshot(SensorSnapshot)
    case pong(String)
    case failure(String)

    private enum CodingKeys: String, CodingKey {
        case kind
        case descriptor
        case snapshot
        case label
        case message
    }

    private enum Kind: String, Codable {
        case ack
        case descriptor
        case snapshot
        case pong
        case failure
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .ack:
            self = .ack
        case .descriptor:
            self = .descriptor(try container.decode(MacModelDescriptor.self, forKey: .descriptor))
        case .snapshot:
            self = .snapshot(try container.decode(SensorSnapshot.self, forKey: .snapshot))
        case .pong:
            self = .pong(try container.decode(String.self, forKey: .label))
        case .failure:
            self = .failure(try container.decode(String.self, forKey: .message))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .ack:
            try container.encode(Kind.ack, forKey: .kind)
        case .descriptor(let descriptor):
            try container.encode(Kind.descriptor, forKey: .kind)
            try container.encode(descriptor, forKey: .descriptor)
        case .snapshot(let snapshot):
            try container.encode(Kind.snapshot, forKey: .kind)
            try container.encode(snapshot, forKey: .snapshot)
        case .pong(let label):
            try container.encode(Kind.pong, forKey: .kind)
            try container.encode(label, forKey: .label)
        case .failure(let message):
            try container.encode(Kind.failure, forKey: .kind)
            try container.encode(message, forKey: .message)
        }
    }
}

enum HelperCodec {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func encodeLine<T: Encodable>(_ value: T) throws -> Data {
        var data = try encoder.encode(value)
        data.append(UInt8(ascii: "\n"))
        return data
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder.decode(type, from: data)
    }
}
