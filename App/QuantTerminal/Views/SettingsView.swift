import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var tokenDraft = ""

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                TextField("https://tu-servidor", text: $model.serverURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Servidor")
            } footer: {
                Text("HTTPS, o la IP privada de tu VPN (p. ej. Tailscale 100.x.y.z).")
            }
            Section {
                if model.hasToken {
                    Label("Token guardado en el Llavero", systemImage: "checkmark.seal")
                    Button("Olvidar token", role: .destructive) { model.forgetToken() }
                } else {
                    SecureField("qtd_…", text: $tokenDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Guardar") {
                        model.saveToken(tokenDraft)
                        tokenDraft = ""
                        Task { await model.refresh() }
                    }
                    .disabled(tokenDraft.isEmpty)
                }
            } header: {
                Text("Token del dispositivo")
            } footer: {
                Text("Créalo con POST /api/v1/devices usando el token de operador. Se muestra una sola vez.")
            }
            Section("Alertas push") {
                Button("Activar notificaciones") { Task { await model.requestPushPermission() } }
                if let status = model.pushStatus { Text(status).font(.footnote) }
            }
        }
        .navigationTitle("Ajustes")
    }
}
