import Foundation

#if os(macOS)
import IOKit
#endif

#if os(macOS)
enum AppleSMCMethod {
    static let kernelIndex: UInt32 = 2
}

enum AppleSMCCommand {
    static let readBytes: UInt8 = 5
    static let writeBytes: UInt8 = 6
    static let readIndex: UInt8 = 8
    static let readKeyInfo: UInt8 = 9
}

struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

struct SMCPowerLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPowerLimit: UInt32 = 0
    var gpuPowerLimit: UInt32 = 0
    var memoryPowerLimit: UInt32 = 0
}

struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

struct SMCKeyData {
    var key: UInt32 = 0
    var version = SMCVersion()
    var powerLimitData = SMCPowerLimitData()
    var keyInfo = SMCKeyInfoData()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
        (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

enum AppleSMCKeyCodec {
    static func fourCC(from key: IntelSMCKey) -> UInt32 {
        key.rawValue.utf8.reduce(0) { partial, scalar in
            (partial << 8) | UInt32(scalar)
        }
    }

    static func string(from value: UInt32) -> String {
        let chars: [UInt8] = [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff),
        ]
        return String(decoding: chars, as: UTF8.self)
    }
}

enum AppleSMCByteCodec {
    static func encode(_ data: Data) -> SMCKeyData {
        var result = SMCKeyData()
        let count = min(data.count, MemoryLayout.size(ofValue: result.bytes))
        withUnsafeMutableBytes(of: &result.bytes) { buffer in
            buffer.baseAddress?.assumingMemoryBound(to: UInt8.self).initialize(from: data.prefix(count), count: count)
        }
        return result
    }

    static func decode(_ bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                 UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                 UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                 UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8),
                       count: Int) -> Data {
        var copy = bytes
        return withUnsafeBytes(of: &copy) { rawBuffer in
            Data(rawBuffer.prefix(count))
        }
    }
}
#endif
