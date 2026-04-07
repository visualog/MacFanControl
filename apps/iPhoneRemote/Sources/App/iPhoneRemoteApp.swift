import SwiftUI

@main
struct iPhoneRemoteApp: App {
    @State private var store = RemoteDashboardStore.live

    var body: some Scene {
        WindowGroup {
            RemoteRootView(store: store)
        }
    }
}
