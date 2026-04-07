import Foundation
import RemoteProtocol
import SharedModels

protocol RemoteControlClient: Sendable {
    func discoverDevices() async throws -> [RemoteDeviceDescriptor]
    func connect(to device: RemoteDeviceDescriptor) async throws -> DeviceStatus
    func fetchProfiles() async throws -> [FanProfile]
    func applyProfile(_ profile: ProfileKind) async throws -> ValidationResponse
}

struct RemoteDeviceDescriptor: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let name: String
    let host: String
    let port: Int
    let transport: String
}

struct PreviewRemoteControlClient: RemoteControlClient {
    let previewStatus: DeviceStatus
    let previewProfiles: [FanProfile]

    func discoverDevices() async throws -> [RemoteDeviceDescriptor] {
        [
            .init(
                id: UUID(),
                name: "MacBook Pro 16",
                host: "mfc.local",
                port: 48484,
                transport: "ws"
            )
        ]
    }

    func connect(to device: RemoteDeviceDescriptor) async throws -> DeviceStatus {
        previewStatus
    }

    func fetchProfiles() async throws -> [FanProfile] {
        previewProfiles
    }

    func applyProfile(_ profile: ProfileKind) async throws -> ValidationResponse {
        ValidationResponse(
            accepted: true,
            reason: "Profile \(profile.rawValue) queued for validation on the Mac."
        )
    }
}
