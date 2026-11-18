import Foundation
import Observation
import QuantKit
import UIKit
import UserNotifications

@MainActor
@Observable
final class AppModel {
    var overview: Overview?
    var errorMessage: String?
    var isLoading = false
    var isStopping = false
    var lastStopMessage: String?
    var pushStatus: String?
    var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: "serverURL") }
    }
    var hasToken: Bool

    private let tokens = KeychainTokenStore()

    init() {
        serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? ""
        hasToken = KeychainTokenStore().token() != nil
    }

    private func client() throws -> QuantAPIClient {
        guard let url = URL(string: serverURL.trimmingCharacters(in: .whitespaces)), url.host != nil else {
            throw QuantAPIError.server(status: 0, detail: "Configura la URL del servidor en Ajustes")
        }
        return try QuantAPIClient(baseURL: url, tokens: tokens)
    }

    func saveToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        hasToken = !trimmed.isEmpty && tokens.save(trimmed)
    }

    func forgetToken() {
        tokens.delete()
        hasToken = false
        overview = nil
    }

    func refresh() async {
        guard hasToken, !serverURL.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            overview = try await client().overview()
            errorMessage = nil
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    func emergencyStop() async {
        isStopping = true
        defer { isStopping = false }
        do {
            let response = try await client().emergencyStop(reason: "parada de emergencia desde iOS")
            lastStopMessage = response.message
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            await refresh()
        } catch {
            errorMessage = Self.describe(error)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    func requestPushPermission() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
                pushStatus = "Registrando…"
            } else {
                pushStatus = "Notificaciones denegadas en Ajustes de iOS"
            }
        } catch {
            pushStatus = error.localizedDescription
        }
    }

    func registerPush(_ deviceToken: Data) async {
        #if DEBUG
        let environment = PushEnvironment.sandbox
        #else
        let environment = PushEnvironment.production
        #endif
        do {
            try await client().registerPushToken(deviceToken, environment: environment)
            pushStatus = "Alertas activadas (\(environment.rawValue))"
        } catch {
            pushStatus = Self.describe(error)
        }
    }

    static func describe(_ error: Error) -> String {
        guard let error = error as? QuantAPIError else { return error.localizedDescription }
        switch error {
        case .missingToken: return "Falta el token del dispositivo"
        case .insecureServer: return "El servidor debe usar HTTPS (o una IP de VPN privada)"
        case .unauthorized: return "Token no válido o revocado"
        case .forbidden: return "Este token no tiene permiso para esa acción"
        case .controlDisabled: return "El servidor no tiene TERMINAL_ADMIN_TOKEN: controles deshabilitados"
        case .conflict(let detail): return detail
        case .server(let status, let detail): return status == 0 ? detail : "Error \(status): \(detail)"
        case .network: return "Sin conexión con el servidor"
        case .decoding: return "Respuesta inesperada del servidor"
        }
    }
}
