import ActionsWatcherCore
import SwiftUI

struct DashboardView: View {
    @ObservedObject var store: MonitorStore
    private var active: [RunRecord] { store.visibleRecords.filter { $0.run.state.isActive } }
    private var recent: [RunRecord] { store.visibleRecords.filter { !$0.run.state.isActive } }

    var body: some View {
        VStack(spacing: 16) {
            summary.padding(.horizontal, 22).padding(.top, 20)
            HStack(spacing: 4) {
                ForEach(RunFilter.allCases, id: \.self) { filter in
                    Button { store.filter = filter } label: {
                        HStack(spacing: 6) {
                            Text(filter.rawValue)
                            if filter == .active && store.activeCount > 0 {
                                Text("\(store.activeCount)").font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                    .background(Theme.accent.opacity(0.15), in: Capsule())
                            }
                        }.font(.system(size: 11, weight: .medium)).frame(maxWidth: .infinity).padding(.vertical, 8)
                            .foregroundStyle(store.filter == filter ? Theme.primary : Theme.secondary)
                            .background(store.filter == filter ? Theme.raised : .clear, in: RoundedRectangle(cornerRadius: 7))
                    }.buttonStyle(HandButtonStyle())
                }
            }.padding(4).background(Theme.surface, in: RoundedRectangle(cornerRadius: 10)).padding(.horizontal, 22)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                TextField("Buscar repositorio, rama o workflow…", text: $store.search)
                    .textFieldStyle(.plain).font(.system(size: 11))
                if !store.search.isEmpty {
                    Button { store.search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(HandButtonStyle()).foregroundStyle(Theme.muted).accessibilityLabel("Limpiar búsqueda")
                }
            }.padding(.horizontal, 22)

            ScrollView {
                LazyVStack(spacing: 11) {
                    if let error = store.errorMessage { ErrorBanner(message: error) }
                    else if !store.repositoryErrors.isEmpty {
                        ErrorBanner(message: "Algunos repositorios no se pudieron actualizar. Mostramos el último estado conocido.")
                    }
                    if store.isDemo {
                        Text("Vista de demostración · los estados no se actualizan.")
                            .font(.system(size: 10)).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if store.selectedRepositories.isEmpty { emptyRepositories }
                    else if store.visibleRecords.isEmpty { emptyRuns }
                    else {
                        if !active.isEmpty {
                            SectionLabel(title: "EN CURSO", trailing: "\(active.count)").padding(.top, 2)
                            ForEach(active) { record in row(record) }
                        }
                        if !recent.isEmpty {
                            SectionLabel(title: store.filter == .failed ? "FALLIDAS" : "RECIENTES", trailing: "\(recent.count)")
                                .padding(.top, active.isEmpty ? 2 : 8)
                            ForEach(recent) { record in row(record) }
                        }
                    }
                }.padding(.horizontal, 22).padding(.bottom, 20)
            }.scrollIndicators(.hidden)
        }
    }

    private var summary: some View {
        VStack(spacing: 16) {
          HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle().stroke(store.summary.color.opacity(0.15), lineWidth: 5).frame(width: 45, height: 45)
                StatusIcon(state: store.summary, size: 23)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(headline).font(.system(size: 17, weight: .semibold)).tracking(-0.5)
                Text("\(store.selectedRepositories.count) repositorios · GitHub Actions")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 0)
            Text("CI").font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.muted).padding(7).overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border))
          }
          if !store.records.isEmpty {
              RunActivityStrip(records: store.records) { store.selectRun($0) }
          }
        }.padding(16).background(
            LinearGradient(colors: [store.summary.color.opacity(0.075), Theme.surface], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 13)
        ).overlay(RoundedRectangle(cornerRadius: 13).stroke(store.summary.color.opacity(0.12), lineWidth: 1))
    }

    private var headline: String {
        if !store.repositoryErrors.isEmpty { return "Sincronización pendiente" }
        if store.activeCount > 0 { return "\(store.activeCount) \(store.activeCount == 1 ? "ejecución activa" : "ejecuciones activas")" }
        if store.summary == .failure { return "Algo necesita tu atención" }
        if store.summary == .success { return "Todo en verde" }
        return "Tu próximo push empieza aquí"
    }

    private func row(_ record: RunRecord) -> some View {
        Button { store.selectRun(record) } label: {
            RunRow(record: record, stale: store.repositoryErrors[record.repository] != nil)
        }.buttonStyle(HandButtonStyle()).accessibilityLabel("\(record.repository), \(record.run.workflowName), \(record.run.state.label). Ver jobs y pasos")
    }

    private var emptyRepositories: some View {
        EmptyState(symbol: "square.stack.3d.up", title: "Elige qué quieres seguir", message: "Tus workflows aparecerán aquí después de seleccionar un repositorio.") {
            Button("Elegir repositorios") { store.screen = .repositories }.buttonStyle(AccentButton())
        }
    }

    private var emptyRuns: some View {
        EmptyState(symbol: store.isRefreshing ? "arrow.clockwise" : "tray", title: store.isRefreshing ? "Buscando ejecuciones…" : "Sin ejecuciones aquí",
            message: store.search.isEmpty && store.filter == .all ? "Cuando ejecutes un workflow, podrás seguirlo desde aquí." : "Prueba con otro filtro o término de búsqueda.") { EmptyView() }
    }
}

struct RunRow: View {
    let record: RunRecord
    var stale = false
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            StatusIcon(state: record.run.state, size: 18).padding(.top, 2)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text(record.run.workflowName).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(stale ? "Sin actualizar" : record.run.state.label)
                        .font(.system(size: 9, weight: .medium)).foregroundStyle(stale ? Theme.warning : record.run.state.color)
                }
                Text(record.repository).font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.secondary).lineLimit(1)
                Text(record.run.title).font(.system(size: 11)).foregroundStyle(Theme.secondary.opacity(0.85)).lineLimit(1)
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 9))
                    Text(record.run.headBranch ?? "sin rama").lineLimit(1).truncationMode(.middle)
                    Text("· #\(record.run.runNumber)")
                    Spacer(minLength: 4)
                    Image(systemName: "stopwatch").font(.system(size: 9))
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(elapsed(record.run, now: context.date)).monospacedDigit()
                    }
                }.font(.system(size: 9)).foregroundStyle(Theme.muted)
            }
        }.padding(13).frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering ? Theme.raised : Theme.surface, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(hovering ? Theme.accent.opacity(0.22) : Theme.border))
            .contentShape(RoundedRectangle(cornerRadius: 11)).onHover { hovering = $0 }
    }
}

struct EmptyState<Action: View>: View {
    let symbol: String
    let title: String
    let message: String
    @ViewBuilder let action: () -> Action
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 29, weight: .light)).foregroundStyle(Theme.accent).padding(.top, 28)
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(message).font(.system(size: 11)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            action()
        }.padding(24).frame(maxWidth: .infinity)
    }
}
