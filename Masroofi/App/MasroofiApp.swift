import SwiftUI
import SwiftData
import MasroofiCore

@main
struct MasroofiApp: App {
    @AppStorage("didFinishSetup", store: AppSettings.defaults) private var didFinishSetup = false

    var body: some Scene {
        WindowGroup {
            Group {
                if didFinishSetup { RootTabView() } else { SetupFlowView() }
            }
            .tint(Theme.accent)
            .task { CycleReset.runIfNeeded(context: Store.container.mainContext) }
        }
        .modelContainer(Store.container)
    }
}

struct RootTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Today", systemImage: "sun.max.fill") }
            ActivityView()
                .tabItem { Label("Activity", systemImage: "list.bullet.rectangle") }
            BudgetsView()
                .tabItem { Label("Budgets", systemImage: "chart.pie.fill") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}
