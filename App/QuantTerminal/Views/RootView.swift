import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            NavigationStack { OverviewView() }
                .tabItem { Label("Resumen", systemImage: "chart.line.uptrend.xyaxis") }
            NavigationStack { AlertsView() }
                .tabItem { Label("Alertas", systemImage: "bell") }
                .badge(model.overview?.alerts.filter { $0.severity == .critical }.count ?? 0)
            NavigationStack { SettingsView() }
                .tabItem { Label("Ajustes", systemImage: "gear") }
        }
        .task {
            while !Task.isCancelled {
                await model.refresh()
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }
}
