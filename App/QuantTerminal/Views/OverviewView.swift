import Charts
import QuantKit
import SwiftUI

struct OverviewView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            if let error = model.errorMessage {
                Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            }
            if let overview = model.overview {
                Section("Bots") {
                    LabeledContent("Motor", value: Self.label(overview.bot.status))
                    LabeledContent("Paper trader") {
                        Text(overview.trader.alive ? "activo" : "sin latido")
                            .foregroundStyle(overview.trader.alive ? .green : .red)
                    }
                    if let venue = overview.trader.venue { LabeledContent("Venue", value: venue) }
                    if let strategy = overview.strategy {
                        LabeledContent("Estrategia", value: "\(strategy.name) · \(strategy.timeframe)")
                        if strategy.gatePassed == false {
                            Text("Promovida sin superar la validación").font(.footnote).foregroundStyle(.orange)
                        }
                    } else {
                        Text("Ninguna estrategia en paper trading").foregroundStyle(.secondary)
                    }
                    if let reason = overview.trader.haltedReason {
                        Text(reason).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("P&L (\(overview.pnl.currency))") {
                    LabeledContent("Equity", value: overview.pnl.equity.formatted(.number.precision(.fractionLength(2))))
                    LabeledContent("P&L") {
                        Text(overview.pnl.pnl.formatted(.number.precision(.fractionLength(2)).sign(strategy: .always())))
                            .foregroundStyle(overview.pnl.pnl >= 0 ? .green : .red)
                    }
                    LabeledContent("Rentabilidad", value: overview.pnl.returnPct.formatted(.percent.precision(.fractionLength(2))))
                    LabeledContent("Posición", value: "\(overview.pnl.position) BTC")
                    if overview.pnl.equityCurve.count > 1 {
                        EquityChart(points: overview.pnl.equityCurve).frame(height: 180)
                    }
                }
                Section {
                    KillSwitchButton()
                } footer: {
                    Text(overview.disclaimer)
                }
            } else if model.hasToken {
                ProgressView("Cargando…")
            } else {
                ContentUnavailableView("Sin configurar", systemImage: "key",
                                       description: Text("Añade la URL del servidor y el token del dispositivo en Ajustes."))
            }
        }
        .navigationTitle("Quant")
        .refreshable { await model.refresh() }
    }

    static func label(_ status: BotState.Status) -> String {
        switch status {
        case .running: "en marcha"
        case .paused: "en pausa"
        case .panic: "PARADA DE EMERGENCIA"
        }
    }
}

struct EquityChart: View {
    let points: [EquityPoint]

    var body: some View {
        Chart(points) { point in
            LineMark(x: .value("Hora", point.at), y: .value("Equity", NSDecimalNumber(decimal: point.equity).doubleValue))
        }
        .chartYScale(domain: .automatic(includesZero: false))
    }
}
