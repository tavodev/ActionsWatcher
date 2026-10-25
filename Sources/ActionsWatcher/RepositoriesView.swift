import ActionsWatcherCore
import SwiftUI

struct RepositoriesView: View {
    @ObservedObject var store: MonitorStore
    @State private var search = ""
    @State private var manualRepository = ""
    @State private var isAdding = false

    private var visibleRepositories: [Repository] {
        var repositories = store.repositories
        let known = Set(repositories.map(\.fullName))
        for (index, name) in store.selectedRepositories.sorted().enumerated() where !known.contains(name) {
            repositories.append(Repository(id: -index - 1, fullName: name))
        }
        return repositories.filter { search.isEmpty || $0.fullName.localizedCaseInsensitiveContains(search) }.sorted {
            let first = store.selectedRepositories.contains($0.fullName), second = store.selectedRepositories.contains($1.fullName)
            return first != second ? first : $0.fullName.localizedStandardCompare($1.fullName) == .orderedAscending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            PageHeading(title: "Tus repositorios", subtitle: "Elige hasta 10 proyectos para seguir su CI.") { store.screen = .dashboard }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                TextField("Buscar en tus repositorios…", text: $search).textFieldStyle(.plain)
            }.padding(11).background(Theme.surface, in: RoundedRectangle(cornerRadius: 9))

            HStack(spacing: 7) {
                TextField("propietario/repositorio o URL", text: $manualRepository).textFieldStyle(.plain)
                    .font(.system(size: 11)).onSubmit { addRepository() }
                Button { addRepository() } label: {
                    if isAdding { ProgressView().controlSize(.small) }
                    else { Image(systemName: "plus").foregroundStyle(Theme.accent) }
                }.buttonStyle(HandButtonStyle()).disabled(isAdding || manualRepository.isEmpty)
                    .accessibilityLabel("Añadir repositorio")
            }.padding(11).overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.border))

            if let error = store.errorMessage { ErrorBanner(message: error) { store.errorMessage = nil } }
            SectionLabel(title: "REPOSITORIOS", trailing: "\(store.selectedRepositories.count) de 10 seleccionados")

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(visibleRepositories, id: \.fullName) { repo in
                        Button { store.toggleRepository(repo.fullName) } label: {
                            HStack(spacing: 11) {
                                Image(systemName: store.selectedRepositories.contains(repo.fullName) ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 17)).foregroundStyle(store.selectedRepositories.contains(repo.fullName) ? Theme.accent : Theme.muted)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(repo.name).font(.system(size: 12, weight: .medium))
                                    Text(repo.fullName).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.secondary)
                                }.lineLimit(1)
                                Spacer(minLength: 0)
                                if repo.archived { Text("Archivado").font(.system(size: 9)).foregroundStyle(Theme.muted) }
                                if repo.isPrivate { Image(systemName: "lock").font(.system(size: 10)).foregroundStyle(Theme.muted) }
                            }.padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 10)).contentShape(Rectangle())
                        }.buttonStyle(HandButtonStyle()).accessibilityLabel("\(repo.fullName), \(store.selectedRepositories.contains(repo.fullName) ? "seleccionado" : "sin seleccionar")")
                    }
                    if visibleRepositories.isEmpty {
                        Text("No encontramos repositorios. Prueba con otro nombre o añade uno por URL.")
                            .font(.system(size: 11)).foregroundStyle(Theme.secondary).padding(.vertical, 25)
                    }
                    if store.canLoadMoreRepositories {
                        Button(store.isLoadingRepositories ? "Cargando…" : "Cargar más repositorios") {
                            Task { await store.loadMoreRepositories() }
                        }.buttonStyle(HandButtonStyle()).foregroundStyle(Theme.accent).disabled(store.isLoadingRepositories).padding(12)
                    }
                }
            }.scrollIndicators(.hidden)

            Button { store.screen = .dashboard; Task { await store.refresh() } } label: {
                Text(store.selectedRepositories.isEmpty ? "Continuar sin repositorios" : "Monitorear \(store.selectedRepositories.count) repositorios")
            }.buttonStyle(AccentButton())
        }.padding(22)
    }

    private func addRepository() {
        guard !isAdding, !manualRepository.isEmpty else { return }
        isAdding = true
        Task {
            if await store.addRepository(manualRepository) { manualRepository = "" }
            isAdding = false
        }
    }
}
