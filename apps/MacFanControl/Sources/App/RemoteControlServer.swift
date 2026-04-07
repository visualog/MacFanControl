import Foundation
import Observation
import RemoteProtocol
import SharedModels

@Observable
final class RemoteControlServer {
    var configuration: RemoteServerConfiguration
    var pairedDevices: [PairedRemoteDevice]
    var lastTelemetryEvent: TelemetryEvent?
    var serverState: ServerState

    init(
        configuration: RemoteServerConfiguration,
        pairedDevices: [PairedRemoteDevice],
        lastTelemetryEvent: TelemetryEvent? = nil,
        serverState: ServerState
    ) {
        self.configuration = configuration
        self.pairedDevices = pairedDevices
        self.lastTelemetryEvent = lastTelemetryEvent
        self.serverState = serverState
    }

    func publish(status: DeviceStatus) {
        lastTelemetryEvent = .status(status)
        serverState.lastPublishedAt = status.snapshot.timestamp
    }

    func beginPairing() -> PairingStartResponse {
        let response = PairingStartResponse(
            sessionID: UUID(),
            code: String(Int.random(in: 100_000 ... 999_999)),
            expiresAt: Date().addingTimeInterval(180)
        )

        serverState.activePairingCode = response.code
        serverState.lastPairingStartedAt = Date()
        return response
    }

    func acceptPreviewDevice(named name: String) {
        pairedDevices.append(
            PairedRemoteDevice(
                id: UUID(),
                name: name,
                pairedAt: .now,
                lastSeenAt: .now,
                trustLevel: .trusted
            )
        )
    }
}

struct RemoteServerConfiguration: Sendable, Hashable {
    let bonjourServiceName: String
    let websocketPath: String
    let requiresLocalNetwork: Bool

    init(
        bonjourServiceName: String,
        websocketPath: String = "/telemetry",
        requiresLocalNetwork: Bool = true
    ) {
        self.bonjourServiceName = bonjourServiceName
        self.websocketPath = websocketPath
        self.requiresLocalNetwork = requiresLocalNetwork
    }
}

struct PairedRemoteDevice: Identifiable, Sendable, Hashable {
    enum TrustLevel: String, Sendable {
        case trusted
        case limited
        case revoked
    }

    let id: UUID
    let name: String
    let pairedAt: Date
    var lastSeenAt: Date
    var trustLevel: TrustLevel
}

struct ServerState: Sendable, Hashable {
    var isListening: Bool
    var boundPort: Int
    var activePairingCode: String?
    var lastPairingStartedAt: Date?
    var lastPublishedAt: Date?

    init(
        isListening: Bool,
        boundPort: Int,
        activePairingCode: String? = nil,
        lastPairingStartedAt: Date? = nil,
        lastPublishedAt: Date? = nil
    ) {
        self.isListening = isListening
        self.boundPort = boundPort
        self.activePairingCode = activePairingCode
        self.lastPairingStartedAt = lastPairingStartedAt
        self.lastPublishedAt = lastPublishedAt
    }
}

extension RemoteControlServer {
    static let preview = RemoteControlServer(
        configuration: .init(bonjourServiceName: LocalTransport.bonjourServiceType),
        pairedDevices: [
            .init(
                id: UUID(),
                name: "Visualog iPhone",
                pairedAt: .now.addingTimeInterval(-86_400),
                lastSeenAt: .now.addingTimeInterval(-45),
                trustLevel: .trusted
            ),
            .init(
                id: UUID(),
                name: "QA iPhone",
                pairedAt: .now.addingTimeInterval(-172_800),
                lastSeenAt: .now.addingTimeInterval(-310),
                trustLevel: .limited
            ),
        ],
        serverState: .init(
            isListening: true,
            boundPort: LocalTransport.defaultPort,
            activePairingCode: "483921",
            lastPairingStartedAt: .now.addingTimeInterval(-20),
            lastPublishedAt: .now.addingTimeInterval(-2)
        )
    )
}
