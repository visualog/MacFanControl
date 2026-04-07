import SwiftUI
import SharedModels

struct RemoteRootView: View {
    let store: RemoteDashboardStore

    var body: some View {
        TabView(selection: Bindable(store).selectedTab) {
            NavigationStack {
                RemoteLiveView(store: store)
            }
            .tabItem {
                Label("Live", systemImage: "fanblades")
            }
            .tag(RemoteTab.live)

            NavigationStack {
                RemoteProfilesView(store: store)
            }
            .tabItem {
                Label("Profiles", systemImage: "slider.horizontal.3")
            }
            .tag(RemoteTab.profiles)
        }
        .task {
            await store.refreshDiscovery()
            await store.loadRemoteState()
        }
    }
}

private struct RemoteLiveView: View {
    let store: RemoteDashboardStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                RemoteHeroCard(
                    deviceName: store.deviceName,
                    connectionState: store.connectionState,
                    status: store.status
                )

                RemoteFanCards(fans: store.status.snapshot.fans)

                RemoteTemperatureList(temperatures: store.status.snapshot.temperatures)

                RemoteSafetyCard(
                    status: store.status.safety,
                    message: store.validationMessage
                )
            }
            .padding(20)
        }
        .navigationTitle("Live")
    }
}

private struct RemoteProfilesView: View {
    let store: RemoteDashboardStore

    var body: some View {
        List {
            Section("Discovered Macs") {
                ForEach(store.discoveredDevices) { device in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(device.name)
                            Text("\(device.host):\(device.port)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(device.transport.uppercased())
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Quick Profiles") {
                ForEach(store.availableProfiles, id: \.kind) { profile in
                    ProfileRow(
                        profile: profile,
                        isSelected: store.selectedProfile == profile.kind,
                        apply: {
                            Task {
                                await store.requestProfile(profile.kind)
                            }
                        }
                    )
                }
            }

            Section("Policy") {
                Text("The Mac remains the safety authority and can reject unsafe requests.")
                Text(store.validationMessage)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Profiles")
    }
}

private struct RemoteHeroCard: View {
    let deviceName: String
    let connectionState: String
    let status: DeviceStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(deviceName)
                .font(.system(size: 30, weight: .bold, design: .rounded))

            Text(connectionState)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                RemoteBadge(title: "Mode", value: status.mode.rawValue)
                RemoteBadge(title: "Profile", value: status.activeProfile?.rawValue ?? "auto")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [.orange.opacity(0.22), .red.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24)
        )
    }
}

private struct RemoteFanCards: View {
    let fans: [FanReading]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(fans, id: \.id) { fan in
                VStack(alignment: .leading, spacing: 8) {
                    Text("Fan \(fan.id + 1)")
                        .font(.headline)
                    Text("\(fan.currentRPM)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text(fan.targetRPM.map { "Target \($0)" } ?? "Auto")
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
            }
        }
    }
}

private struct RemoteTemperatureList: View {
    let temperatures: [TemperatureReading]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Temperatures")
                .font(.title3.weight(.semibold))

            ForEach(temperatures, id: \.name) { item in
                HStack {
                    Text(item.name)
                    Spacer()
                    Text("\(item.celsius, specifier: "%.1f") C")
                        .fontWeight(.semibold)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(18)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct RemoteSafetyCard: View {
    let status: SafetyStatus
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Safety")
                .font(.title3.weight(.semibold))
            Text(status.isEmergencyOverrideActive ? "Emergency override active" : "Normal operating state")
                .font(.headline)
            Text(status.reason.capitalized)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct ProfileRow: View {
    let profile: FanProfile
    let isSelected: Bool
    let apply: () -> Void

    var body: some View {
        Button(action: apply) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.name)
                    Text(profile.kind.rawValue.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct RemoteBadge: View {
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
        .background(Color.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    RemoteRootView(store: .preview)
}
