import SwiftUI

/// Two steps on purpose: the button opens a confirmation, the confirmation pulls the switch.
struct KillSwitchButton: View {
    @Environment(AppModel.self) private var model
    @State private var confirming = false

    var body: some View {
        let inPanic = model.overview?.bot.status == .panic
        Button(role: .destructive) {
            confirming = true
        } label: {
            HStack {
                Image(systemName: "stop.octagon.fill")
                Text(inPanic ? "Parada de emergencia activa" : "Parada de emergencia")
                Spacer()
                if model.isStopping { ProgressView() }
            }
            .font(.headline)
        }
        .disabled(inPanic || model.isStopping)
        .confirmationDialog("¿Detener todo el trading?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Sí, parar y cancelar órdenes", role: .destructive) {
                Task { await model.emergencyStop() }
            }
        } message: {
            Text("El servidor deja de enviar órdenes y cancela las abiertas. Reanudar requiere el token de operador.")
        }
        if let message = model.lastStopMessage {
            Text(message).font(.footnote).foregroundStyle(.secondary)
        }
    }
}
