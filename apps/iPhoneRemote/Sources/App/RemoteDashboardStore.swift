import Foundation
import Observation
import RemoteProtocol
import SharedModels

@MainActor
@Observable
final class RemoteDashboardStore {
    private let client: any RemoteControlClient

    var selectedTab: RemoteTab
    var deviceName: String
    var connectionState: String
    var status: DeviceStatus
    var availableProfiles: [FanProfile]
    var selectedProfile: ProfileKind
    var validationMessage: String
    var discoveredDevices: [RemoteDeviceDescriptor]
    var connectedDevice: RemoteDeviceDescriptor?

    init(
        client: any RemoteControlClient,
        selectedTab: RemoteTab,
        deviceName: String,
        connectionState: String,
        status: DeviceStatus,
        availableProfiles: [FanProfile],
        selectedProfile: ProfileKind,
        validationMessage: String,
        discoveredDevices: [RemoteDeviceDescriptor],
        connectedDevice: RemoteDeviceDescriptor? = nil
    ) {
        self.client = client
        self.selectedTab = selectedTab
        self.deviceName = deviceName
        self.connectionState = connectionState
        self.status = status
        self.availableProfiles = availableProfiles
        self.selectedProfile = selectedProfile
        self.validationMessage = validationMessage
        self.discoveredDevices = discoveredDevices
        self.connectedDevice = connectedDevice
    }

    func refreshDiscovery() async {
        do {
            discoveredDevices = try await client.discoverDevices()
            if let first = discoveredDevices.first {
                deviceName = first.name
                connectionState = "Discovered on \(first.host):\(first.port)"
                connectedDevice = first
            }
        } catch {
            connectionState = "Discovery failed"
        }
    }

    func loadRemoteState() async {
        guard let connectedDevice else { return }

        do {
            status = try await client.connect(to: connectedDevice)
            availableProfiles = try await client.fetchProfiles()
            if let activeProfile = status.activeProfile {
                selectedProfile = activeProfile
            }
            validationMessage = status.safety.reason.capitalized
        } catch {
            validationMessage = "Failed to load remote state."
        }
    }

    func requestProfile(_ profile: ProfileKind) async {
        do {
            let response = try await client.applyProfile(profile)
            validationMessage = response.reason
            await loadRemoteState()
        } catch {
            validationMessage = "Profile request failed."
        }
    }
}

enum RemoteTab: Hashable {
    case live
    case profiles
}

extension RemoteDashboardStore {
    static var live: RemoteDashboardStore {
        RemoteDashboardStore(
            client: NetworkRemoteControlClient(),
            selectedTab: .live,
            deviceName: "Searching…",
            connectionState: "Looking for Macs on the local network",
            status: .init(
                mode: .fallback,
                activeProfile: nil,
                snapshot: .init(
                    timestamp: .now,
                    temperatures: [],
                    fans: [],
                    isExternalDisplayConnected: false,
                    isClamshellMode: false
                ),
                safety: .init(isEmergencyOverrideActive: false, reason: "awaiting connection")
            ),
            availableProfiles: [],
            selectedProfile: .balanced,
            validationMessage: "Waiting for a nearby Mac Fan Control host.",
            discoveredDevices: [],
            connectedDevice: nil
        )
    }

    static var preview: RemoteDashboardStore {
        RemoteDashboardStore(
            client: PreviewRemoteControlClient(
                previewStatus: .init(
                    mode: .profile,
                    activeProfile: .balanced,
                    snapshot: .init(
                        timestamp: .now,
                        temperatures: [
                            .init(name: "CPU Proximity", celsius: 77.9),
                            .init(name: "GPU Diode", celsius: 73.4),
                            .init(name: "Palm Rest", celsius: 32.8),
                        ],
                        fans: [
                            .init(id: 0, currentRPM: 2910, targetRPM: 3000),
                            .init(id: 1, currentRPM: 2895, targetRPM: 3000),
                        ],
                        isExternalDisplayConnected: true,
                        isClamshellMode: false
                    ),
                    safety: .init(isEmergencyOverrideActive: false, reason: "profile applied")
                ),
                previewProfiles: [
                    .init(kind: .quiet, name: "Quiet", curve: []),
                    .init(kind: .balanced, name: "Balanced", curve: []),
                    .init(kind: .performance, name: "Performance", curve: []),
                    .init(kind: .custom, name: "Custom Curve", curve: []),
                ]
            ),
            selectedTab: .live,
            deviceName: "MacBook Pro 16",
            connectionState: "Connected on local network",
            status: .init(
                mode: .profile,
                activeProfile: .balanced,
                snapshot: .init(
                    timestamp: .now,
                    temperatures: [
                        .init(name: "CPU Proximity", celsius: 77.9),
                        .init(name: "GPU Diode", celsius: 73.4),
                        .init(name: "Palm Rest", celsius: 32.8),
                    ],
                    fans: [
                        .init(id: 0, currentRPM: 2910, targetRPM: 3000),
                        .init(id: 1, currentRPM: 2895, targetRPM: 3000),
                    ],
                    isExternalDisplayConnected: true,
                    isClamshellMode: false
                ),
                safety: .init(isEmergencyOverrideActive: false, reason: "profile applied")
            ),
            availableProfiles: [
                .init(kind: .quiet, name: "Quiet", curve: []),
                .init(kind: .balanced, name: "Balanced", curve: []),
                .init(kind: .performance, name: "Performance", curve: []),
                .init(kind: .custom, name: "Custom Curve", curve: []),
            ],
            selectedProfile: .balanced,
            validationMessage: "Remote requests are validated on the Mac before they are applied.",
            discoveredDevices: [
                .init(
                    id: UUID(),
                    name: "MacBook Pro 16",
                    host: "mfc.local",
                    port: 48484,
                    transport: "ws"
                )
            ],
            connectedDevice: .init(
                id: UUID(),
                name: "MacBook Pro 16",
                host: "mfc.local",
                port: 48484,
                transport: "ws"
            )
        )
    }
}
