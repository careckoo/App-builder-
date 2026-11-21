import SwiftUI
import SwiftData
import WidgetKit
import KhurdaCore

@main
struct KhurdaApp: App {
    @AppStorage("didFinishSetup", store: AppSettings.defaults) private var didFinishSetup = false
    @AppStorage("appearance", store: AppSettings.defaults) private var appearance = Appearance.light
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if didFinishSetup { RootTabView() } else { SetupFlowView() }
            }
            .tint(Theme.accent)
            .preferredColorScheme(appearance.colorScheme)
            .task { CycleReset.runIfNeeded(context: Store.container.mainContext) }
        }
        .modelContainer(Store.container)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            // Payday may have passed while the app sat in the background.
            case .active: CycleReset.runIfNeeded(context: Store.container.mainContext)
            // Edits made in the app (category, delete, fixed-bill toggle) should reach the widget.
            case .background: WidgetCenter.shared.reloadAllTimelines()
            default: break
            }
        }
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
                .tabItem { Label("Plan", systemImage: "chart.pie.fill") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}
