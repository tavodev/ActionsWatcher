import ActionsWatcherCore
import SwiftUI

struct RunDetailView: View {
    @ObservedObject var store: MonitorStore
    let record: RunRecord
    @State private var copied = false
    @State private var selectedJobID: Int?
    @State private var showAllJobs = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var progress: WorkflowProgress { WorkflowProgress(jobs: store.jobs) }
    private var focusedJob: WorkflowJob? { JobFocus.preferred(in: store.jobs, selectedID: selectedJobID) }
    private var displayedJobs: [WorkflowJob] {
        let ordered = JobFocus.ordered(store.jobs)
        if showAllJobs { return ordered }
        var visible = Array(ordered.prefix(4))
        if let focusedJob, !visible.contains(where: { $0.id == focusedJob.id }), !visible.isEmpty {
            visible[visible.count - 1] = focusedJob
        }
        return visible
    }

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    HStack(alignment: .top, spacing: 6) {
                        PageHeading(title: record.run.workflowName, subtitle: record.repository) { store.closeRun() }
                        IconButton(symbol: copied ? "checkmark" : "link", label: copied ? "Enlace copiado" : "Copiar enlace de la ejecución") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(record.run.htmlURL.absoluteString, forType: .string)
                            copied = true
                        }.disabled(store.isDemo)
                    }.id("run-top")
                    overview

                    if let error = store.jobsError {
                        ErrorBanner(message: error)
                        Button("Reintentar") { Task { await store.loadJobs(record) } }
                            .buttonStyle(HandButtonStyle()).foregroundStyle(Theme.accent)
                    }
                    if store.jobsLoading && store.jobs.isEmpty {
                        loadingMap
                    } else if store.jobs.isEmpty {
                        EmptyState(symbol: "clock", title: "Esperando al primer runner",
                            message: "El mapa aparecerá cuando GitHub publique los jobs de esta ejecución.") { EmptyView() }
                    } else {
                        HStack {
                            SectionLabel(title: "MAPA DE JOBS", trailing: "\(store.jobs.count) jobs")
                            if store.jobsLoading { ProgressView().controlSize(.mini) }
                        }
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                            ForEach(displayedJobs) { job in
                                JobTile(job: job, isSelected: focusedJob?.id == job.id) {
                                    selectedJobID = job.id
                                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
                                        reader.scrollTo("job-inspector", anchor: .top)
                                    }
                                }
                            }
                        }
                        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.88),
                            value: displayedJobs.map { "\($0.id)/\($0.status)/\($0.conclusion ?? "")" })

                        if store.jobs.count > 4 {
                            Button {
                                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { showAllJobs.toggle() }
                            } label: {
                                HStack(spacing: 5) {
                                    Text(showAllJobs ? "Mostrar menos jobs" : "Ver los \(store.jobs.count) jobs")
                                    Image(systemName: showAllJobs ? "chevron.up" : "chevron.down").font(.system(size: 8))
                                }.font(.system(size: 10)).frame(maxWidth: .infinity)
                            }.buttonStyle(HandButtonStyle()).foregroundStyle(Theme.secondary)
                        }

                        if let job = focusedJob {
                            VStack(alignment: .leading, spacing: 12) {
                                SectionLabel(title: "EXPLORAR JOB")
                                JobInspector(job: job).id(job.id)
                                Button {
                                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                                        reader.scrollTo("run-top", anchor: .top)
                                    }
                                } label: {
                                    Label("Volver al mapa", systemImage: "arrow.up")
                                        .font(.system(size: 10)).frame(maxWidth: .infinity)
                                }.buttonStyle(HandButtonStyle()).foregroundStyle(Theme.secondary)
                            }.id("job-inspector")
                        }
                    }
                    if store.isDemo {
                        Text("Demostración · progreso y jobs de ejemplo.")
                            .font(.system(size: 10)).foregroundStyle(Theme.muted)
                    }
                    Button { openGitHub(record.run.htmlURL) } label: {
                        Label("Abrir ejecución en GitHub", systemImage: "arrow.up.right")
                    }.buttonStyle(AccentButton()).disabled(store.isDemo)
                }.padding(22)
            }.scrollIndicators(.hidden)
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 20) {
                CompletionRing(progress: progress, state: record.run.state)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        StatePill(state: record.run.state)
                        Spacer(minLength: 0)
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(elapsed(record.run, now: context.date)).font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Theme.secondary).monospacedDigit()
                        }
                    }
                    Text(record.run.title).font(.system(size: 13, weight: .semibold))
                        .lineLimit(2).help(record.run.title)
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.triangle.branch").font(.system(size: 9))
                        Text(record.run.headBranch ?? "sin rama").lineLimit(1).truncationMode(.middle)
                        Text("· #\(record.run.runNumber) · intento \(record.run.attempt)")
                    }.font(.system(size: 9)).foregroundStyle(Theme.muted)
                }
            }
            Rectangle().fill(Theme.border).frame(height: 1)
            HStack(spacing: 0) {
                metric(progress.succeeded, "Exitosos", Theme.success)
                metric(progress.running, "En curso", Theme.accent)
                metric(progress.queued, "En espera", Theme.warning)
                metric(progress.failed, "Fallidos", Theme.failure)
            }
            let otherFinished = progress.finished - progress.succeeded - progress.failed
            if otherFinished > 0 {
                Text("\(otherFinished) jobs cancelados u omitidos")
                    .font(.system(size: 8)).foregroundStyle(Theme.muted)
            }
        }.surface().animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: progress)
    }

    private func metric(_ value: Int, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value)").font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(color).monospacedDigit().contentTransition(.numericText())
            Text(label).font(.system(size: 8)).foregroundStyle(Theme.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
    }

    private var loadingMap: some View {
        VStack(spacing: 13) {
            ActivityGlyph(state: .running, size: 27)
            Text("Preparando el mapa de jobs…").font(.system(size: 11)).foregroundStyle(Theme.secondary)
        }.frame(maxWidth: .infinity).padding(.vertical, 30)
    }
}

struct JobInspector: View {
    let job: WorkflowJob
    @State private var selectedStepNumber: Int?
    @State private var showAllSteps = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var steps: [WorkflowStep] { (job.steps ?? []).sorted { $0.number < $1.number } }
    private var progress: WorkflowProgress { WorkflowProgress(steps: steps) }
    private var current: WorkflowStep? {
        steps.first { $0.state == .running } ?? steps.first { $0.state == .failure } ??
            steps.first { $0.state == .queued } ?? steps.last
    }
    private var selected: WorkflowStep? {
        steps.first { $0.number == selectedStepNumber } ?? current
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(alignment: .top, spacing: 11) {
                ActivityGlyph(state: job.state, size: 22).padding(.top, 1)
                VStack(alignment: .leading, spacing: 5) {
                    Text(job.name).font(.system(size: 14, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                    Text("\(progress.finished) de \(progress.total) pasos terminados")
                        .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 0)
            }
            if steps.isEmpty {
                Text("GitHub todavía no ha publicado los pasos de este job.")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
            } else {
                StepRail(steps: steps, selection: selected?.number, following: selectedStepNumber == nil) { number in
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { selectedStepNumber = number }
                }
                if let selected {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text(selected.state == .running ? "EN EJECUCIÓN" : "PASO \(selected.number) · \(selected.state.label.uppercased())")
                                .font(.system(size: 8, weight: .semibold)).tracking(1.3).foregroundStyle(selected.state.color)
                            Spacer()
                            if selectedStepNumber != nil && selected.number != current?.number {
                                Button("Seguir actual") { selectedStepNumber = nil }
                                    .font(.system(size: 9)).buttonStyle(HandButtonStyle()).foregroundStyle(Theme.accent)
                            }
                        }
                        Text(selected.compactName).font(.system(size: 13, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true).help(selected.name).textSelection(.enabled)
                    }.padding(13).frame(maxWidth: .infinity, alignment: .leading)
                        .background(selected.state.color.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected.state.color.opacity(0.18)))
                }
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { showAllSteps.toggle() }
                } label: {
                    HStack {
                        Text(showAllSteps ? "Ocultar detalle de pasos" : "Ver los \(steps.count) pasos")
                        Spacer()
                        Image(systemName: showAllSteps ? "chevron.up" : "chevron.down").font(.system(size: 8))
                    }.font(.system(size: 10)).contentShape(Rectangle())
                }.buttonStyle(HandButtonStyle()).foregroundStyle(Theme.secondary)
                if showAllSteps {
                    VStack(spacing: 0) {
                        ForEach(steps) { step in
                            HStack(alignment: .top, spacing: 11) {
                                VStack(spacing: 4) {
                                    ActivityGlyph(state: step.state, size: 12)
                                    Rectangle().fill(Theme.border).frame(width: 1).frame(minHeight: 14)
                                }.frame(width: 16)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(step.compactName).font(.system(size: 10, weight: step.state == .running ? .semibold : .regular))
                                        .foregroundStyle(step.state.isActive ? Theme.primary : Theme.secondary)
                                        .fixedSize(horizontal: false, vertical: true).help(step.name).textSelection(.enabled)
                                    Text("PASO \(step.number) · \(step.state.label)")
                                        .font(.system(size: 7, weight: .medium)).foregroundStyle(Theme.muted)
                                }.padding(.bottom, 16)
                                Spacer(minLength: 0)
                            }
                        }
                    }.transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }.surface()
    }
}

private struct StepRail: View {
    let steps: [WorkflowStep]
    let selection: Int?
    let following: Bool
    let select: (Int) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        if index > 0 {
                            Rectangle().fill(steps[index - 1].state == .success ? Theme.success.opacity(0.6) : Theme.raised)
                                .frame(width: 13, height: 2).padding(.bottom, 14)
                        }
                        Button { select(step.number) } label: {
                            VStack(spacing: 5) {
                                ZStack {
                                    Circle().fill(step.state.color.opacity(step.number == selection ? 0.16 : 0.06))
                                    if step.state == .queued {
                                        Circle().stroke(Theme.raised, lineWidth: 1.5)
                                        Circle().fill(Theme.muted.opacity(0.5)).frame(width: 4, height: 4)
                                    } else { ActivityGlyph(state: step.state, size: 14) }
                                }.frame(width: 27, height: 27)
                                    .overlay(Circle().stroke(step.number == selection ? step.state.color.opacity(0.9) : .clear, lineWidth: 1.3))
                                Text("\(step.number)").font(.system(size: 7, weight: .medium, design: .monospaced))
                                    .foregroundStyle(step.number == selection ? Theme.primary : Theme.muted)
                            }.padding(.vertical, 2)
                        }.buttonStyle(HandButtonStyle()).id(step.number)
                            .help("\(step.number). \(step.name) · \(step.state.label)")
                            .accessibilityLabel("Paso \(step.number), \(step.name), \(step.state.label)")
                    }
                }.padding(.horizontal, 2)
            }.scrollIndicators(.hidden)
                .onAppear { if let selection { reader.scrollTo(selection, anchor: .center) } }
                .onChange(of: selection) { _, number in
                    guard following, let number else { return }
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { reader.scrollTo(number, anchor: .center) }
                }
        }
    }
}
