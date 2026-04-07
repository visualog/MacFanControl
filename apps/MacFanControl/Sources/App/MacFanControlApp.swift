import SwiftUI

@main
struct MacFanControlApp: App {
    @State private var controller = MacDashboardController.preview

    var body: some Scene {
        MenuBarExtra("MFC", systemImage: "fan") {
            MacDashboardView(controller: controller)
                .frame(width: 360)
        }
        .menuBarExtraStyle(.window)

        WindowGroup("Mac Fan Control") {
            MacDashboardView(controller: controller)
                .frame(minWidth: 760, minHeight: 560)
        }
    }
}
