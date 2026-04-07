import SwiftUI
import SharedModels

struct MacDashboardView: View {
    let controller: MacDashboardController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                MacHeaderCard(
                    modelIdentifier: controller.modelDescriptor.identifier,
                    mode: controller.mode,
                    profileName: controller.activeProfile.name,
                    safetyStatus: controller.safetyStatus
                )

                MacProfilesSection(
                    profiles: controller.availableProfiles,
                    activeProfile: controller.activeProfile
                )

                MacFansSection(fans: controller.snapshot.fans)

                MacTemperaturesSection(temperatures: controller.snapshot.temperatures)

                MacCommandSection(
                    summary: controller.lastCommandSummary,
                    snapshot: controller.snapshot
                )

                MacServerSection(server: controller.remoteServer)

                MacPairingSection(pairedDevices: controller.remoteServer.pairedDevices)
            }
            .padding(20)
        }
        .background(.windowBackground)
        .task {
            controller.startRemoteServices()
            controller.refreshFromHardwareIfAvailable()
            controller.publishPreviewTelemetry()
        }
    }
}

private struct MacHeaderCard: View {
    let modelIdentifier: String
    let mode: DeviceMode
    let profileName: String
    let safetyStatus: SafetyStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mac Fan Control")
                .font(.system(size: 24, weight: .semibold, design: .rounded))

            Text(modelIdentifier)
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                StatusPill(title: "Mode", value: mode.rawValue)
                StatusPill(title: "Profile", value: profileName)
                StatusPill(
                    title: "Safety",
                    value: safetyStatus.isEmergencyOverrideActive ? "Emergency" : "Normal"
                )
            }

            Text(safetyStatus.reason.capitalized)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct MacProfilesSection: View {
    let profiles: [FanProfile]
    let activeProfile: FanProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Profiles")
                .font(.title3.weight(.semibold))

            ForEach(profiles, id: \.kind) { profile in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.name)
                            .font(.headline)
                        Text(profile.kind.rawValue.capitalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if profile.kind == activeProfile.kind {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                .padding(14)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }
}

private struct MacFansSection: View {
    let fans: [FanReading]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fans")
                .font(.title3.weight(.semibold))

            ForEach(fans, id: \.id) { fan in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Fan \(fan.id + 1)")
                            .font(.headline)
                        Text("Current \(fan.currentRPM) RPM")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(fan.targetRPM.map { "Target \($0)" } ?? "Auto")
                        .font(.system(.body, design: .rounded))
                }
                .padding(14)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }
}

private struct MacTemperaturesSection: View {
    let temperatures: [TemperatureReading]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Temperatures")
                .font(.title3.weight(.semibold))

            ForEach(temperatures, id: \.name) { reading in
                HStack {
                    Text(reading.name)
                    Spacer()
                    Text("\(reading.celsius, specifier: "%.1f") C")
                        .font(.headline)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct MacCommandSection: View {
    let summary: String
    let snapshot: SensorSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Control Reason")
                .font(.title3.weight(.semibold))

            Text(summary)
                .font(.body)

            HStack(spacing: 10) {
                StatusPill(
                    title: "External Display",
                    value: snapshot.isExternalDisplayConnected ? "Connected" : "Off"
                )
                StatusPill(
                    title: "Clamshell",
                    value: snapshot.isClamshellMode ? "On" : "Off"
                )
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct MacServerSection: View {
    let server: RemoteControlServer

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Remote Server")
                .font(.title3.weight(.semibold))

            HStack(spacing: 10) {
                StatusPill(title: "State", value: server.serverState.isListening ? "Listening" : "Stopped")
                StatusPill(title: "Port", value: "\(server.serverState.boundPort)")
                StatusPill(title: "Path", value: server.configuration.websocketPath)
            }

            Text("Bonjour: \(server.configuration.bonjourServiceName)")
                .foregroundStyle(.secondary)

            if let code = server.serverState.activePairingCode {
                Text("Active pairing code: \(code)")
                    .font(.subheadline.weight(.medium))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct MacPairingSection: View {
    let pairedDevices: [PairedRemoteDevice]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Paired iPhone Devices")
                .font(.title3.weight(.semibold))

            if pairedDevices.isEmpty {
                Text("No paired devices yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(pairedDevices, id: \.self) { device in
                    HStack {
                        Image(systemName: "iphone")
                        Text(device.name)
                        Spacer()
                        Text(device.trustLevel.rawValue.capitalized)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct StatusPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    MacDashboardView(controller: .preview)
        .frame(width: 760, height: 560)
}
