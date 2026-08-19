import SwiftUI

@main
struct MacFanApp: App {
    @StateObject private var model: AppModel = AppModel()

    var body: some Scene {
        MenuBarExtra {
            DashboardView(model: model)
                .onAppear {
                    model.start()
                }
        } label: {
            Label("app.title", systemImage: "fan")
        }
        .menuBarExtraStyle(.window)
    }
}
