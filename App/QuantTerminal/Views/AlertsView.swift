import QuantKit
import SwiftUI

struct AlertsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List(model.overview?.alerts ?? []) { alert in
            VStack(alignment: .leading, spacing: 4) {
                Label(alert.title, systemImage: Self.icon(alert.severity))
                    .foregroundStyle(Self.color(alert.severity))
                Text(alert.body).font(.subheadline)
                Text(alert.at).font(.caption).foregroundStyle(.secondary)
            }
        }
        .overlay {
            if (model.overview?.alerts ?? []).isEmpty {
                ContentUnavailableView("Sin alertas", systemImage: "bell.slash")
            }
        }
        .navigationTitle("Alertas")
        .refreshable { await model.refresh() }
    }

    static func icon(_ severity: AlertItem.Severity) -> String {
        switch severity {
        case .critical: "exclamationmark.octagon.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .info: "info.circle"
        }
    }

    static func color(_ severity: AlertItem.Severity) -> Color {
        switch severity {
        case .critical: .red
        case .warning: .orange
        case .info: .primary
        }
    }
}
