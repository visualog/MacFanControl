import Foundation
import SharedModels

#if os(macOS)
import IOKit
#endif

public final class IntelSMCController: SMCControlling {
    private let transport: any IntelSMCTransport
    private let sensorProfile: [IntelSensorDefinition]
    private let modelIdentifierProvider: @Sendable () -> String

    public init(
        transport: any IntelSMCTransport,
        sensorProfile: [IntelSensorDefinition] = IntelMacModelProfiles.macBookPro16_1Sensors,
        modelIdentifierProvider: @escaping @Sendable () -> String = {
            Host.current().localizedName ?? "IntelMac"
        }
    ) {
        self.transport = transport
        self.sensorProfile = sensorProfile
        self.modelIdentifierProvider = modelIdentifierProvider
    }

    public func readModelDescriptor() throws -> MacModelDescriptor {
        let fan0 = FanCapability(
            id: 0,
            minimumRPM: try readRPM(for: .fan0MinimumRPM),
            maximumRPM: try readRPM(for: .fan0MaximumRPM)
        )
        let fan1 = FanCapability(
            id: 1,
            minimumRPM: try readRPM(for: .fan1MinimumRPM),
            maximumRPM: try readRPM(for: .fan1MaximumRPM)
        )

        return MacModelDescriptor(
            identifier: modelIdentifierProvider(),
            fanCapabilities: [fan0, fan1]
        )
    }

    public func readSnapshot() throws -> SensorSnapshot {
        let temperatures = try sensorProfile.compactMap { sensor in
            let reading = try transport.read(key: sensor.key)
            let celsius = try IntelSMCValueDecoder.decodeTemperature(from: reading)
            return TemperatureReading(name: sensor.displayName, celsius: celsius)
        }

        let fan0Current = try readRPM(for: .fan0CurrentRPM)
        let fan1Current = try readRPM(for: .fan1CurrentRPM)
        let fan0Target = try? readRPM(for: .fan0TargetRPM)
        let fan1Target = try? readRPM(for: .fan1TargetRPM)

        return SensorSnapshot(
            timestamp: .now,
            temperatures: temperatures,
            fans: [
                FanReading(id: 0, currentRPM: fan0Current, targetRPM: fan0Target),
                FanReading(id: 1, currentRPM: fan1Current, targetRPM: fan1Target),
            ],
            isExternalDisplayConnected: false,
            isClamshellMode: false
        )
    }

    public func setFanRPM(_ rpm: Int, fanID: Int) throws {
        let key: IntelSMCKey = fanID == 0 ? .fan0TargetRPM : .fan1TargetRPM
        try setFanMode(for: fanID, forced: true)
        try transport.write(
            key: key,
            bytes: IntelSMCValueDecoder.encodeRPM(rpm)
        )
    }

    public func revertFanToAuto(fanID: Int) throws {
        try setFanMode(for: fanID, forced: false)
    }

    private func readRPM(for key: IntelSMCKey) throws -> Int {
        let reading = try transport.read(key: key)
        return try IntelSMCValueDecoder.decodeRPM(from: reading)
    }

    private func setFanMode(for fanID: Int, forced: Bool) throws {
        let existingMode = (try? transport.read(key: .fanMode)).flatMap { reading in
            reading.bytes.first
        } ?? 0

        var mode = IntelFanMode(rawValue: existingMode)
        let bit: IntelFanMode = fanID == 0 ? .fan0Forced : .fan1Forced

        if forced {
            mode.insert(bit)
        } else {
            mode.remove(bit)
        }

        try transport.write(key: .fanMode, bytes: Data([mode.rawValue]))
    }
}

public protocol IntelSMCTransport: Sendable {
    func read(key: IntelSMCKey) throws -> IntelSMCReading
    func write(key: IntelSMCKey, bytes: Data) throws
}

#if os(macOS)
public final class AppleSMCTransport: IntelSMCTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var connection: io_connect_t = 0

    public init() {}

    deinit {
        close()
    }

    public func read(key: IntelSMCKey) throws -> IntelSMCReading {
        lock.lock()
        defer { lock.unlock() }

        try openIfNeeded()

        let keyCode = AppleSMCKeyCodec.fourCC(from: key)
        var input = SMCKeyData()
        var output = SMCKeyData()

        input.key = keyCode
        input.data8 = AppleSMCCommand.readKeyInfo
        try callKernel(input: &input, output: &output)

        let rawType = AppleSMCKeyCodec.string(from: output.keyInfo.dataType)
        let dataType = IntelSMCDataType(rawValue: rawType) ?? .bytes
        let dataSize = Int(output.keyInfo.dataSize)

        input.keyInfo.dataSize = output.keyInfo.dataSize
        input.data8 = AppleSMCCommand.readBytes
        try callKernel(input: &input, output: &output)

        let bytes = AppleSMCByteCodec.decode(output.bytes, count: dataSize)
        return IntelSMCReading(key: key, dataType: dataType, bytes: bytes)
    }

    public func write(key: IntelSMCKey, bytes: Data) throws {
        lock.lock()
        defer { lock.unlock() }

        try openIfNeeded()

        let keyCode = AppleSMCKeyCodec.fourCC(from: key)
        var input = AppleSMCByteCodec.encode(bytes)
        var output = SMCKeyData()

        input.key = keyCode
        input.data8 = AppleSMCCommand.readKeyInfo
        try callKernel(input: &input, output: &output)

        input.keyInfo = output.keyInfo
        input.data8 = AppleSMCCommand.writeBytes
        input.key = keyCode
        try callKernel(input: &input, output: &output)
    }

    private func openIfNeeded() throws {
        guard connection == 0 else { return }

        guard let matching = IOServiceMatching("AppleSMC") else {
            throw SMCBridgeError.notOpen
        }

        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else {
            throw SMCBridgeError.notOpen
        }

        defer { IOObjectRelease(service) }

        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard result == kIOReturnSuccess else {
            connection = 0
            throw SMCBridgeError.notOpen
        }
    }

    private func close() {
        lock.lock()
        defer { lock.unlock() }

        guard connection != 0 else { return }
        IOServiceClose(connection)
        connection = 0
    }

    private func callKernel(input: inout SMCKeyData, output: inout SMCKeyData) throws {
        var outputSize = MemoryLayout<SMCKeyData>.stride
        let result = withUnsafePointer(to: &input) { inputPointer in
            withUnsafeMutablePointer(to: &output) { outputPointer in
                IOConnectCallStructMethod(
                    connection,
                    AppleSMCMethod.kernelIndex,
                    inputPointer,
                    MemoryLayout<SMCKeyData>.stride,
                    outputPointer,
                    &outputSize
                )
            }
        }

        guard result == kIOReturnSuccess else {
            throw SMCBridgeError.readFailed("AppleSMC call failed with code \(result)")
        }
    }
}
#else
public final class AppleSMCTransport: IntelSMCTransport, @unchecked Sendable {
    public init() {}

    public func read(key: IntelSMCKey) throws -> IntelSMCReading {
        throw SMCBridgeError.unsupportedPlatform
    }

    public func write(key: IntelSMCKey, bytes: Data) throws {
        throw SMCBridgeError.unsupportedPlatform
    }
}
#endif
