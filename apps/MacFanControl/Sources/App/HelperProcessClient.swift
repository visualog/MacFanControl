import Foundation
import SharedModels
import SMCBridge

@MainActor
final class HelperProcessClient {
    private let logger: FanControlLogger
    private let environment: [String: String]

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var readBuffer = Data()

    var lastErrorDescription: String?

    init(
        logger: FanControlLogger,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.logger = logger
        self.environment = environment
    }

    func connectIfPossible() -> Bool {
        if process?.isRunning == true {
            return true
        }

        guard let executableURL = resolveExecutableURL() else {
            lastErrorDescription = "Helper executable path is unavailable."
            return false
        }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.executableURL = executableURL
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        process.environment = environment

        do {
            try process.run()
            self.process = process
            self.stdinHandle = inputPipe.fileHandleForWriting
            self.stdoutHandle = outputPipe.fileHandleForReading
            lastErrorDescription = nil
            logger.info("Started helper process at \(executableURL.path).")
            return true
        } catch {
            lastErrorDescription = error.localizedDescription
            logger.error("Failed to launch helper process: \(error.localizedDescription)")
            return false
        }
    }

    func loadDescriptor() -> MacModelDescriptor? {
        guard let response = send(.loadDescriptor) else { return nil }
        switch response {
        case .descriptor(let descriptor):
            lastErrorDescription = nil
            return descriptor
        case .failure(let message):
            lastErrorDescription = message
            return nil
        default:
            lastErrorDescription = "Unexpected helper response for descriptor."
            return nil
        }
    }

    func loadSnapshot() -> SensorSnapshot? {
        guard let response = send(.loadSnapshot) else { return nil }
        switch response {
        case .snapshot(let snapshot):
            lastErrorDescription = nil
            return snapshot
        case .failure(let message):
            lastErrorDescription = message
            return nil
        default:
            lastErrorDescription = "Unexpected helper response for snapshot."
            return nil
        }
    }

    func applyTargetRPM(_ rpm: Int) -> Bool {
        guard let response = send(.applyTargetRPM(rpm)) else { return false }
        switch response {
        case .ack:
            lastErrorDescription = nil
            return true
        case .failure(let message):
            lastErrorDescription = message
            return false
        default:
            lastErrorDescription = "Unexpected helper response for applyTargetRPM."
            return false
        }
    }

    func revertAllFansToAuto() -> Bool {
        guard let response = send(.revertAllFansToAuto) else { return false }
        switch response {
        case .ack:
            lastErrorDescription = nil
            return true
        case .failure(let message):
            lastErrorDescription = message
            return false
        default:
            lastErrorDescription = "Unexpected helper response for revertAllFansToAuto."
            return false
        }
    }

    private func send(_ command: HelperCommand) -> HelperResponse? {
        guard connectIfPossible() else { return nil }
        guard let stdinHandle, let stdoutHandle else {
            lastErrorDescription = "Helper process pipes are not available."
            return nil
        }

        do {
            let encoded = try HelperCodec.encodeLine(command)
            try stdinHandle.write(contentsOf: encoded)
            let line = try readLine(from: stdoutHandle)
            let response = try HelperCodec.decode(HelperResponse.self, from: line)
            return response
        } catch {
            lastErrorDescription = error.localizedDescription
            logger.error("Helper process IPC failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func readLine(from handle: FileHandle) throws -> Data {
        while true {
            if let newlineIndex = readBuffer.firstIndex(of: UInt8(ascii: "\n")) {
                let frame = readBuffer.prefix(upTo: newlineIndex)
                readBuffer.removeSubrange(...newlineIndex)
                return Data(frame)
            }

            let chunk = try handle.read(upToCount: 4096) ?? Data()
            if chunk.isEmpty {
                throw HelperProcessClientError.unexpectedEOF
            }
            readBuffer.append(chunk)
        }
    }

    private func resolveExecutableURL() -> URL? {
        if let helperPath = environment["MFC_HELPER_PATH"], helperPath.isEmpty == false {
            return URL(fileURLWithPath: helperPath)
        }

        let bundleCandidate = Bundle.main.bundleURL
            .appending(path: "Contents")
            .appending(path: "Helpers")
            .appending(path: "MacFanControlHelper")
        if FileManager.default.isExecutableFile(atPath: bundleCandidate.path) {
            return bundleCandidate
        }

        let derivedDataCandidate = URL(fileURLWithPath: "/tmp/MFCDerivedData-Mac/Build/Products/Debug/MacFanControlHelper")
        if FileManager.default.isExecutableFile(atPath: derivedDataCandidate.path) {
            return derivedDataCandidate
        }

        return nil
    }
}

enum HelperProcessClientError: Error {
    case unexpectedEOF
}
