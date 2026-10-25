import ServiceManagement
import SwiftUI
import UserNotifications

struct SettingsView: View {
    @ObservedObject var store: MonitorStore
    @State private var confirmSignOut = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 21) {
                PageHeading(title: "A tu ritmo", subtitle: "Un poco de calma para tu barra de menús.") { store.screen = .dashboard }
                if let error = store.errorMessage { ErrorBanner(message: error) { store.errorMessage = nil } }

                VStack(alignment: .leading, spacing: 15) {
                    SectionLabel(title: "MONITOREO")
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Actualizar cada").font(.system(size: 12, weight: .medium))
                            Text("Menos consultas cuando no hay cambios.").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                        }
                        Spacer()
                        Picker("Intervalo", selection: $store.refreshInterval) {
                            Text("15 segundos").tag(15)
                            Text("30 segundos").tag(30)
                            Text("1 minuto").tag(60)
                            Text("2 minutos").tag(120)
                        }.labelsHidden().frame(width: 125).handCursor()
                            .onChange(of: store.refreshInterval) { _, _ in store.persistSettings() }
                    }
                    Divider().overlay(Theme.border)
                    Toggle(isOn: Binding(get: { store.launchAtLogin }, set: { store.setLaunchAtLogin($0) })) {
                        Text("Abrir al iniciar sesión").font(.system(size: 12, weight: .medium))
                    }.toggleStyle(.switch).controlSize(.small).handCursor()
                }.surface()

                VStack(alignment: .leading, spacing: 16) {
                    SectionLabel(title: "NOTIFICACIONES")
                    Toggle(isOn: $store.notifyFailures) {
                        Label("Cuando falle una ejecución", systemImage: "xmark.circle").font(.system(size: 12))
                    }.toggleStyle(.switch).controlSize(.small).handCursor()
                        .onChange(of: store.notifyFailures) { _, _ in store.persistSettings() }
                    Toggle(isOn: $store.notifySuccesses) {
                        Label("Cuando termine con éxito", systemImage: "checkmark.circle").font(.system(size: 12))
                    }.toggleStyle(.switch).controlSize(.small).handCursor()
                        .onChange(of: store.notifySuccesses) { _, _ in store.persistSettings() }
                    Text("Solo avisamos sobre ejecuciones que viste en curso. Sin una avalancha de avisos al abrir la app.")
                        .font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                    if store.notificationStatus == .notDetermined {
                        Button("Activar notificaciones en macOS") { Task { await store.requestNotifications() } }
                            .font(.system(size: 11)).foregroundStyle(Theme.accent).buttonStyle(HandButtonStyle())
                    } else if store.notificationStatus == .denied {
                        Text("Notificaciones desactivadas en macOS. Puedes habilitarlas en Ajustes del Sistema → Notificaciones → ActionsWatcher.")
                            .font(.system(size: 10)).foregroundStyle(Theme.warning).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Label("Notificaciones autorizadas", systemImage: "checkmark").font(.system(size: 10)).foregroundStyle(Theme.success)
                    }
                }.surface()

                VStack(alignment: .leading, spacing: 13) {
                    SectionLabel(title: "CUENTA")
                    HStack {
                        Label(store.user.map { "@\($0)" } ?? "GitHub", systemImage: "person.crop.circle")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Button(store.isDemo ? "Salir de demo" : "Desconectar") {
                            if store.isDemo { store.exitDemo() } else { confirmSignOut = true }
                        }.font(.system(size: 11)).buttonStyle(HandButtonStyle()).foregroundStyle(Theme.failure)
                    }
                    Text("La app consulta directamente la API de GitHub. No envía información a otros servidores ni modifica tus repositorios.")
                        .font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                }.surface()
                Text("ACTIONSWATCHER  /  1.0.0").font(.system(size: 8, weight: .medium, design: .monospaced))
                    .tracking(1.8).foregroundStyle(Theme.muted).frame(maxWidth: .infinity).padding(.vertical, 3)
            }.padding(22)
        }.scrollIndicators(.hidden)
            .task { await store.updateNotificationStatus() }
            .alert("¿Desconectar tu cuenta?", isPresented: $confirmSignOut) {
                Button("Cancelar", role: .cancel) {}
                Button("Desconectar", role: .destructive) { store.signOut() }
            } message: { Text("Se eliminarán de esta app el token guardado y los repositorios seleccionados. Tu sesión de GitHub CLI se conserva.") }
    }
}
