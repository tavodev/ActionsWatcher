import SwiftUI

struct OnboardingView: View {
    @ObservedObject var store: MonitorStore
    @State private var token = ""
    @State private var showToken = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 13) {
                    Text("MENOS PESTAÑAS. MÁS FLOW.").font(.system(size: 9, weight: .semibold)).tracking(2).foregroundStyle(Theme.accent)
                    Text("Haz push.\nSigue con lo tuyo.")
                        .font(.system(size: 34, weight: .semibold)).tracking(-1.5).lineSpacing(1)
                    Text("Tus builds, tests y deploys de GitHub Actions,\na un clic de distancia.")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary).lineSpacing(5)
                }.padding(.top, 14)

                VStack(spacing: 0) {
                    feature("circle.dotted.circle", "Ve lo que está pasando", "Estado, duración y pasos de cada ejecución.")
                    Rectangle().fill(Theme.border).frame(height: 1).padding(.vertical, 13)
                    feature("bell.badge", "Entérate cuando importa", "Avisos de fallos y éxitos, a tu medida.")
                }.surface()

                VStack(spacing: 12) {
                    Button {
                        Task { await store.connect(token: nil, useCLI: true) }
                    } label: {
                        HStack(spacing: 8) {
                            if store.isConnecting { ProgressView().controlSize(.small).tint(Theme.background) }
                            else { Image(systemName: "terminal") }
                            Text(store.isConnecting ? "Conectando con GitHub…" : "Usar mi sesión de GitHub CLI")
                        }
                    }.buttonStyle(AccentButton()).disabled(store.isConnecting)

                    Button { showToken.toggle() } label: {
                        HStack(spacing: 5) {
                            Text("Conectar con un token personal")
                            Image(systemName: showToken ? "chevron.up" : "chevron.down").font(.system(size: 8))
                        }
                    }.buttonStyle(HandButtonStyle()).font(.system(size: 11)).foregroundStyle(Theme.secondary)

                    if showToken {
                        VStack(alignment: .leading, spacing: 10) {
                            SecureField("Pega tu token de GitHub", text: $token).textFieldStyle(.plain)
                                .padding(11).background(Theme.raised, in: RoundedRectangle(cornerRadius: 8))
                                .onSubmit { connectToken() }
                            Text("Permisos: Actions (lectura) y Metadata (lectura), solo en los repositorios que elijas. Se guarda en Keychain.")
                                .font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                            HStack {
                                Button("Crear token") {
                                    openGitHub(URL(string: "https://github.com/settings/personal-access-tokens/new")!)
                                }.buttonStyle(HandButtonStyle()).foregroundStyle(Theme.accent)
                                Spacer()
                                Button("Conectar") { connectToken() }.handCursor()
                                    .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isConnecting)
                            }.font(.system(size: 11))
                        }.surface()
                    }
                    if let error = store.errorMessage { ErrorBanner(message: error) { store.errorMessage = nil } }
                }

                HStack(spacing: 7) {
                    Image(systemName: "lock.shield").foregroundStyle(Theme.accent)
                    Text("Consultas de lectura · sin servidores intermediarios")
                        .foregroundStyle(Theme.muted)
                }.font(.system(size: 10)).frame(maxWidth: .infinity)

                Button("Explorar una demostración →") { store.enterDemo() }
                    .buttonStyle(HandButtonStyle()).font(.system(size: 11)).foregroundStyle(Theme.secondary).frame(maxWidth: .infinity)
            }.padding(.horizontal, 27).padding(.bottom, 22)
        }.scrollIndicators(.hidden)
            .onDisappear { token = "" }
    }

    private func connectToken() {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let value = token
        Task { await store.connect(token: value, useCLI: false); if store.isConnected { token = "" } }
    }

    private func feature(_ symbol: String, _ title: String, _ subtitle: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: symbol).font(.system(size: 18, weight: .light)).foregroundStyle(Theme.accent).frame(width: 25)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(subtitle).font(.system(size: 10)).foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}
