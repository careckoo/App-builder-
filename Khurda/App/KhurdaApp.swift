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
            .task {
                #if DEBUG
                DemoData.seedIfNeeded(context: Store.container.mainContext)
                #endif
                CycleReset.runIfNeeded(context: Store.container.mainContext)
            }
        }
        .modelContainer(Store.container)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            // Payday may have passed while the app sat in the background.
            case .active:
                CycleReset.runIfNeeded(context: Store.container.mainContext)
                Reminders.reschedule(context: Store.container.mainContext)
            // Edits made in the app (category, delete, fixed-bill toggle) should reach the widget.
            case .background: WidgetCenter.shared.reloadAllTimelines()
            default: break
            }
        }
    }
}

struct RootTabView: View {
    #if DEBUG
    @State private var tab = DemoData.tab
    #else
    @State private var tab = 0
    #endif
    var body: some View {
        TabView(selection: $tab) {
            HomeView()
                .tabItem { Label("Today", systemImage: "sun.max.fill") }.tag(0)
            ActivityView()
                .tabItem { Label("Activity", systemImage: "list.bullet.rectangle") }.tag(1)
            InsightsView()
                .tabItem { Label("Insights", systemImage: "chart.bar.xaxis") }.tag(2)
            BudgetsView()
                .tabItem { Label("Plan", systemImage: "chart.pie.fill") }.tag(3)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }.tag(4)
        }
    }
}
