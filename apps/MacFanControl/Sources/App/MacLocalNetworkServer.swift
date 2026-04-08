import Foundation
import Network
import Observation
import RemoteProtocol
import SharedModels

@MainActor
@Observable
final class MacLocalNetworkServer {
    private let makeStatus: () -> DeviceStatus
    private let makeProfiles: () -> [FanProfile]
    private let applyProfile: (ProfileKind) -> ValidationResponse

    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]

    var listenPort: Int
    var isRunning: Bool
    var lastErrorDescription: String?
    var lastPublishedStatus: DeviceStatus?

    init(
        listenPort: Int = LocalTransport.defaultPort,
        makeStatus: @escaping () -> DeviceStatus,
        makeProfiles: @escaping () -> [FanProfile],
        applyProfile: @escaping (ProfileKind) -> ValidationResponse
    ) {
        self.listenPort = listenPort
        self.isRunning = false
        self.makeStatus = makeStatus
        self.makeProfiles = makeProfiles
        self.applyProfile = applyProfile
    }

    func start() {
        guard listener == nil else { return }

        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true

            let listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: UInt16(listenPort)))
            listener.service = NWListener.Service(name: Host.current().localizedName ?? "Mac Fan Control", type: LocalTransport.bonjourServiceType)
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    self?.handleListenerState(state)
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.accept(connection: connection)
                }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            lastErrorDescription = error.localizedDescription
            isRunning = false
        }
    }

    func stop() {
        connections.values.forEach { $0.cancel() }
        connections.removeAll()
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    func publish(_ status: DeviceStatus) {
        lastPublishedStatus = status
        let response = RemoteResponse.status(status)

        for connection in connections.values {
            send(response, to: connection)
        }
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            isRunning = true
            lastErrorDescription = nil
        case .failed(let error):
            isRunning = false
            lastErrorDescription = error.localizedDescription
        case .cancelled:
            isRunning = false
        default:
            break
        }
    }

    private func accept(connection: NWConnection) {
        let identifier = ObjectIdentifier(connection)
        connections[identifier] = connection

        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handleConnectionState(state, id: identifier)
            }
        }

        connection.start(queue: .main)
        receiveNextMessage(on: connection)
    }

    private func handleConnectionState(_ state: NWConnection.State, id: ObjectIdentifier) {
        switch state {
        case .failed, .cancelled:
            connections[id] = nil
        default:
            break
        }
    }

    private func receiveNextMessage(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self else { return }

                if let error {
                    self.lastErrorDescription = error.localizedDescription
                }

                if let data, !data.isEmpty {
                    self.handleInboundData(data, on: connection)
                }

                if isComplete == false, error == nil {
                    self.receiveNextMessage(on: connection)
                }
            }
        }
    }

    private func handleInboundData(_ data: Data, on connection: NWConnection) {
        for frame in splitFrames(data) {
            do {
                let command = try RemoteCodec.decode(RemoteCommand.self, from: frame)
                let response = handle(command)
                send(response, to: connection)
            } catch {
                send(.error("Invalid command payload"), to: connection)
            }
        }
    }

    private func splitFrames(_ data: Data) -> [Data] {
        let delimiter = UInt8(ascii: "\n")
        return Array(data).split(separator: delimiter).map { Data($0) }
    }

    private func handle(_ command: RemoteCommand) -> RemoteResponse {
        switch command {
        case .fetchStatus:
            return .status(makeStatus())
        case .fetchProfiles:
            return .profiles(makeProfiles())
        case .applyProfile(let request):
            return .validation(applyProfile(request.profile))
        case .validateCurve:
            return .validation(
                ValidationResponse(
                    accepted: true,
                    reason: "Curve validation is reserved for the Mac safety engine."
                )
            )
        }
    }

    private func send(_ response: RemoteResponse, to connection: NWConnection) {
        do {
            let encoded = try RemoteCodec.encodeLine(response)
            connection.send(content: encoded, completion: .contentProcessed { [weak self] error in
                Task { @MainActor in
                    if let error {
                        self?.lastErrorDescription = error.localizedDescription
                    }
                }
            })
        } catch {
            lastErrorDescription = error.localizedDescription
        }
    }
}
