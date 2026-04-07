import Foundation
import Network
import RemoteProtocol
import SharedModels

actor NetworkRemoteControlClient: RemoteControlClient {
    private var browser: NWBrowser?
    private var discoveredEndpoints: [UUID: NWEndpoint] = [:]
    private var activeDeviceID: UUID?
    private let queue = DispatchQueue(label: "com.visualog.mfc.remote-client")

    func discoverDevices() async throws -> [RemoteDeviceDescriptor] {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true

        return try await withCheckedThrowingContinuation { continuation in
            let browser = NWBrowser(
                for: .bonjour(type: LocalTransport.bonjourServiceType, domain: nil),
                using: parameters
            )

            self.browser = browser

            browser.stateUpdateHandler = { state in
                switch state {
                case .failed(let error):
                    browser.cancel()
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }

            browser.browseResultsChangedHandler = { results, _ in
                let discovered = results.compactMap { result -> (RemoteDeviceDescriptor, NWEndpoint)? in
                    guard let descriptor = Self.makeDescriptor(from: result) else { return nil }
                    return (descriptor, result.endpoint)
                }
                let devices = discovered.map(\.0)
                Task {
                    await self.store(discovered)
                }
                browser.cancel()
                continuation.resume(returning: devices)
            }

            browser.start(queue: queue)
        }
    }

    func connect(to device: RemoteDeviceDescriptor) async throws -> DeviceStatus {
        activeDeviceID = device.id
        let response = try await send(.fetchStatus, to: device)
        switch response {
        case .status(let status):
            return status
        case .error(let message):
            throw NetworkRemoteControlError.remote(message)
        default:
            throw NetworkRemoteControlError.unexpectedResponse
        }
    }

    func fetchProfiles() async throws -> [FanProfile] {
        guard let activeDeviceID, let device = descriptor(for: activeDeviceID) else {
            throw NetworkRemoteControlError.noKnownEndpoint
        }

        let response = try await send(.fetchProfiles, to: device)
        switch response {
        case .profiles(let profiles):
            return profiles
        case .error(let message):
            throw NetworkRemoteControlError.remote(message)
        default:
            throw NetworkRemoteControlError.unexpectedResponse
        }
    }

    func applyProfile(_ profile: ProfileKind) async throws -> ValidationResponse {
        guard let activeDeviceID, let device = descriptor(for: activeDeviceID) else {
            throw NetworkRemoteControlError.noKnownEndpoint
        }

        let response = try await send(.applyProfile(.init(profile: profile)), to: device)
        switch response {
        case .validation(let validation):
            return validation
        case .error(let message):
            throw NetworkRemoteControlError.remote(message)
        default:
            throw NetworkRemoteControlError.unexpectedResponse
        }
    }

    private func send(_ command: RemoteCommand, to device: RemoteDeviceDescriptor) async throws -> RemoteResponse {
        let connection: NWConnection

        if let endpoint = discoveredEndpoints[device.id] {
            connection = NWConnection(to: endpoint, using: .tcp)
        } else {
            let host = NWEndpoint.Host(device.host)
            let port = NWEndpoint.Port(integerLiteral: UInt16(device.port))
            connection = NWConnection(host: host, port: port, using: .tcp)
        }

        connection.start(queue: queue)

        let encoded = try RemoteCodec.encodeLine(command)

        return try await withCheckedThrowingContinuation { continuation in
            connection.send(content: encoded, completion: .contentProcessed { error in
                if let error {
                    connection.cancel()
                    continuation.resume(throwing: error)
                    return
                }

                connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, _, receiveError in
                    defer { connection.cancel() }

                    if let receiveError {
                        continuation.resume(throwing: receiveError)
                        return
                    }

                    guard let data, let frame = data.split(separator: UInt8(ascii: "\n")).first else {
                        continuation.resume(throwing: NetworkRemoteControlError.emptyResponse)
                        return
                    }

                    do {
                        let response = try RemoteCodec.decode(RemoteResponse.self, from: Data(frame))
                        continuation.resume(returning: response)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            })
        }
    }

    private func store(_ discovered: [(RemoteDeviceDescriptor, NWEndpoint)]) {
        for item in discovered {
            discoveredEndpoints[item.0.id] = item.1
        }
    }

    private func descriptor(for id: UUID) -> RemoteDeviceDescriptor? {
        guard discoveredEndpoints[id] != nil else { return nil }

        return RemoteDeviceDescriptor(
            id: id,
            name: "Mac Fan Control",
            host: "localhost",
            port: LocalTransport.defaultPort,
            transport: "tcp"
        )
    }

    private static func makeDescriptor(from result: NWBrowser.Result) -> RemoteDeviceDescriptor? {
        guard case .service(let name, _, _, let interface) = result.endpoint else { return nil }

        let host = interface?.name ?? "localhost"

        return RemoteDeviceDescriptor(
            id: UUID(),
            name: name,
            host: host,
            port: LocalTransport.defaultPort,
            transport: "tcp"
        )
    }
}

enum NetworkRemoteControlError: Error {
    case noKnownEndpoint
    case emptyResponse
    case unexpectedResponse
    case remote(String)
}
