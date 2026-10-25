import ActionsWatcherCore
import SwiftUI

struct RootView: View {
    @ObservedObject var store: MonitorStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.border).frame(height: 1)
            Group {
                if let selectedRun = store.selectedRun { RunDetailView(store: store, record: selectedRun) }
                else {
                    switch store.screen {
                    case .onboarding: OnboardingView(store: store)
                    case .dashboard: DashboardView(store: store)
                    case .repositories: RepositoriesView(store: store)
                    case .settings: SettingsView(store: store)
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            Rectangle().fill(Theme.border).frame(height: 1)
            footer
        }
        .frame(width: 460, height: 670)
        .background(Theme.background)
        .foregroundStyle(Theme.primary)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .font(.system(size: 12))
        .environment(\.panelIsActive, store.isPanelVisible)
        .transaction { transaction in
            if !store.isPanelVisible || reduceMotion {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Theme.accent.opacity(0.12)).frame(width: 35, height: 35)
                Image(systemName: "arrow.triangle.branch").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.accent)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("ActionsWatcher").font(.system(size: 16, weight: .semibold, design: .rounded)).tracking(-0.4)
                Text(store.user.map { "@\($0)" } ?? "Tu CI, siempre a la vista.")
                    .font(.system(size: 10)).foregroundStyle(Theme.secondary)
            }
            Spacer()
            if store.isDemo {
                Text("DEMO").font(.system(size: 8, weight: .bold)).tracking(1)
                    .foregroundStyle(Theme.accent).padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Theme.accent.opacity(0.1), in: Capsule())
            }
            if store.isConnected {
                if store.isRefreshing { ProgressView().controlSize(.small).frame(width: 29, height: 29) }
                else { IconButton(symbol: "arrow.clockwise", label: "Actualizar ahora") { Task { await store.refresh() } } }
            }
        }.padding(.horizontal, 22).padding(.vertical, 17)
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Circle().fill(store.errorMessage != nil || !store.repositoryErrors.isEmpty ? Theme.warning :
                (store.isConnected ? Theme.success : Theme.muted)).frame(width: 5, height: 5)
            if store.isDemo {
                Button("Datos de ejemplo · Conectar mi cuenta") { store.exitDemo() }
                    .buttonStyle(HandButtonStyle()).font(.system(size: 10)).foregroundStyle(Theme.secondary)
            } else if let updated = store.lastUpdated {
                TimelineView(.periodic(from: .now, by: 5)) { context in
                    Text(store.repositoryErrors.isEmpty ? "Actualizado \(relativeAge(updated, now: context.date))" : "Datos desactualizados")
                        .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                }
            } else { Text(store.isConnected ? "Listo para monitorear" : "Hecho para tu flujo.").font(.system(size: 10)).foregroundStyle(Theme.muted) }
            Spacer(minLength: 0)
            if store.isConnected {
                IconButton(symbol: "square.stack.3d.up", label: "Repositorios") { navigate(.repositories) }
                IconButton(symbol: "slider.horizontal.3", label: "Preferencias") { navigate(.settings) }
            }
            IconButton(symbol: "power", label: "Salir de ActionsWatcher") { NSApplication.shared.terminate(nil) }
        }.padding(.horizontal, 18).padding(.vertical, 11)
    }

    private func navigate(_ screen: AppScreen) {
        store.closeRun(); store.errorMessage = nil; store.screen = screen
    }
}

private func relativeAge(_ date: Date, now: Date) -> String {
    let seconds = max(0, Int(now.timeIntervalSince(date)))
    if seconds < 10 { return "ahora" }
    if seconds < 60 { return "hace \(seconds) s" }
    if seconds < 3600 { return "hace \(seconds / 60) min" }
    return "hace \(seconds / 3600) h"
}

struct PageHeading: View {
    let title: String
    let subtitle: String
    let back: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconButton(symbol: "chevron.left", label: "Volver") { back() }
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 19, weight: .semibold)).tracking(-0.5).lineLimit(2).help(title)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    .lineLimit(1).truncationMode(.middle).help(subtitle)
            }
            Spacer(minLength: 0)
        }
    }
}
