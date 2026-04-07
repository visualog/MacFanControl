import Foundation

public struct IntelSMCReading: Sendable, Hashable {
    public let key: IntelSMCKey
    public let dataType: IntelSMCDataType
    public let bytes: Data

    public init(key: IntelSMCKey, dataType: IntelSMCDataType, bytes: Data) {
        self.key = key
        self.dataType = dataType
        self.bytes = bytes
    }
}

public struct IntelFanMode: OptionSet, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let fan0Forced = IntelFanMode(rawValue: 1 << 0)
    public static let fan1Forced = IntelFanMode(rawValue: 1 << 1)
}

public enum IntelSMCValueDecoder {
    public static func decodeTemperature(from reading: IntelSMCReading) throws -> Double {
        switch reading.dataType {
        case .signedTemperature:
            return try decodeSP78(from: reading.bytes)
        case .float:
            return try decodeFloat(from: reading.bytes)
        default:
            throw SMCBridgeError.readFailed("Unsupported temperature type \(reading.dataType.rawValue)")
        }
    }

    public static func decodeRPM(from reading: IntelSMCReading) throws -> Int {
        switch reading.dataType {
        case .fixedPoint78:
            return Int(try decodeFPE2(from: reading.bytes).rounded())
        case .float:
            return Int(try decodeFloat(from: reading.bytes).rounded())
        default:
            throw SMCBridgeError.readFailed("Unsupported RPM type \(reading.dataType.rawValue)")
        }
    }

    public static func encodeRPM(_ rpm: Int) -> Data {
        let raw = UInt16(rpm << 2).bigEndian
        return withUnsafeBytes(of: raw) { Data($0) }
    }

    private static func decodeSP78(from bytes: Data) throws -> Double {
        guard bytes.count >= 2 else {
            throw SMCBridgeError.readFailed("SP78 payload too short")
        }

        let signed = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        return Double(signed) / 256.0
    }

    private static func decodeFPE2(from bytes: Data) throws -> Double {
        guard bytes.count >= 2 else {
            throw SMCBridgeError.readFailed("FPE2 payload too short")
        }

        let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
        return Double(raw) / 4.0
    }

    private static func decodeFloat(from bytes: Data) throws -> Double {
        guard bytes.count >= 4 else {
            throw SMCBridgeError.readFailed("Float payload too short")
        }

        let value = bytes.prefix(4).withUnsafeBytes { pointer in
            pointer.load(as: Float.self)
        }
        return Double(value)
    }
}
