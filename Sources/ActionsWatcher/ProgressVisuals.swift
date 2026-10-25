import ActionsWatcherCore
import SwiftUI

private struct PanelIsActiveKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var panelIsActive: Bool {
        get { self[PanelIsActiveKey.self] }
        set { self[PanelIsActiveKey.self] = newValue }
    }
}

struct ActivityGlyph: View {
    let state: RunState
    var size: CGFloat = 20
    var reduceMotionOverride: Bool? = nil
    @Environment(\.panelIsActive) private var panelIsActive
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var animates: Bool { panelIsActive && !(reduceMotionOverride ?? reduceMotion) }

    var body: some View {
        if state == .running {
            TimelineView(.animation(minimumInterval: 1 / 24, paused: !animates)) { context in
                let phase = animates ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2) / 2 : 0.15
                ZStack {
                    Circle().stroke(state.color.opacity(0.18), lineWidth: 1.5)
                    Circle().trim(from: 0, to: 0.7)
                        .stroke(AngularGradient(colors: [state.color.opacity(0.05), state.color], center: .center),
                            style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
                        .rotationEffect(.degrees(phase * 360))
                    Circle().fill(state.color).frame(width: size * 0.24, height: size * 0.24)
                        .opacity(0.7 + 0.3 * sin(phase * .pi * 2))
                }.frame(width: size, height: size)
            }.accessibilityLabel(state.label)
        } else {
            Image(systemName: state.symbol).font(.system(size: size, weight: .medium))
                .foregroundStyle(state.color).frame(width: size, height: size).accessibilityLabel(state.label)
        }
    }
}

struct CompletionRing: View {
    let progress: WorkflowProgress
    let state: RunState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(Theme.raised.opacity(0.8), lineWidth: 6)
            Circle().trim(from: 0, to: progress.fraction)
                .stroke(AngularGradient(colors: [state.color.opacity(0.55), state.color, Theme.accent], center: .center,
                    startAngle: .degrees(0), endAngle: .degrees(360)), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: progress.fraction)
            VStack(spacing: 3) {
                Text(progress.total == 0 ? "—" : "\(progress.finished)")
                    .font(.system(size: 25, weight: .semibold, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText())
                Text(progress.total == 0 ? "JOBS" : "DE \(progress.total) JOBS")
                    .font(.system(size: 7, weight: .semibold)).tracking(1).foregroundStyle(Theme.secondary)
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: progress.finished)
        }.frame(width: 66, height: 66)
            .overlay(alignment: .topTrailing) {
                ActivityGlyph(state: state, size: 16).padding(4).background(Theme.surface, in: Circle()).offset(x: 6, y: -6)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(progress.finished) de \(progress.total) jobs terminados. \(state.label)")
    }
}

struct StepSegments: View {
    let steps: [WorkflowStep]
    let state: RunState
    @Environment(\.panelIsActive) private var panelIsActive
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var animates: Bool { panelIsActive && !reduceMotion && steps.contains { $0.state == .running } }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: !animates)) { timeline in
            // One canvas keeps jobs with many steps lightweight.
            Canvas { context, size in
                let count = max(steps.count, 1)
                let gap = min(3.0, size.width / Double(count) * 0.25)
                let width = max(0.5, (size.width - gap * Double(count - 1)) / Double(count))
                for index in 0..<count {
                    let stepState = steps.isEmpty ? state : steps[index].state
                    let color = stepState == .queued ? Theme.raised : stepState.color
                    let rect = CGRect(x: Double(index) * (width + gap), y: 0, width: width, height: size.height)
                    let path = Path(roundedRect: rect, cornerRadius: 2)
                    context.fill(path, with: .color(color.opacity(stepState == .queued ? 1 : 0.85)))
                    if stepState == .running, animates {
                        let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8) / 1.8
                        var clipped = context
                        clipped.clip(to: path)
                        let gleam = CGRect(x: rect.minX - width * 0.4 + phase * width * 1.4,
                            y: 0, width: width * 0.4, height: size.height)
                        clipped.fill(Path(gleam), with: .color(Theme.primary.opacity(0.85)))
                    }
                }
            }
        }.frame(height: 5).accessibilityHidden(true)
    }
}

struct StatePill: View {
    let state: RunState
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(state.color).frame(width: 4, height: 4)
            Text(state.label).font(.system(size: 9, weight: .medium))
        }.foregroundStyle(state.color).padding(.horizontal, 8).padding(.vertical, 5)
            .background(state.color.opacity(0.08), in: Capsule())
    }
}

struct JobTile: View {
    let job: WorkflowJob
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false
    private var progress: WorkflowProgress { WorkflowProgress(steps: job.steps ?? []) }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ActivityGlyph(state: job.state, size: 18)
                    Spacer()
                    Text(job.state.label).font(.system(size: 8, weight: .medium)).foregroundStyle(job.state.color)
                }
                Text(job.name).font(.system(size: 11, weight: .semibold)).lineLimit(2)
                    .multilineTextAlignment(.leading).frame(maxWidth: .infinity, minHeight: 27, alignment: .topLeading)
                StepSegments(steps: job.steps ?? [], state: job.state)
                HStack {
                    Text(progress.total == 0 ? "Sin pasos publicados" : "\(progress.finished)/\(progress.total) pasos")
                    Spacer(minLength: 0)
                    Image(systemName: isSelected ? "arrow.down.right" : "arrow.up.right")
                }.font(.system(size: 8, weight: .medium)).foregroundStyle(Theme.secondary)
            }.padding(11).frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(colors: [isSelected ? Theme.raised.opacity(0.6) : Theme.surface,
                        Theme.surface], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSelected || hovering ? job.state.color.opacity(0.6) : Theme.border,
                    lineWidth: isSelected ? 1.3 : 1))
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(HandButtonStyle()).onHover { hovering = $0 }
            .help(job.name).accessibilityLabel("\(job.name). \(job.state.label). \(progress.finished) de \(progress.total) pasos terminados. Ver detalle")
    }
}

struct RunActivityStrip: View {
    let records: [RunRecord]
    let select: (RunRecord) -> Void
    private var recent: [RunRecord] {
        Array(records.sorted { $0.run.createdAt > $1.run.createdAt }.prefix(20).reversed())
    }

    var body: some View {
        VStack(spacing: 9) {
            HStack {
                Text("ACTIVIDAD RECIENTE").tracking(1.3)
                Spacer()
                Text("\(recent.count) runs")
            }.font(.system(size: 8, weight: .medium)).foregroundStyle(Theme.muted)
            HStack(alignment: .center, spacing: 5) {
                ForEach(recent) { record in
                    Button { select(record) } label: {
                        RoundedRectangle(cornerRadius: 4).fill(record.run.state.color.opacity(record.run.state.isActive ? 0.15 : 0.7))
                            .overlay {
                                if record.run.state.isActive {
                                    ActivityGlyph(state: record.run.state, size: 11)
                                } else {
                                    Image(systemName: record.run.state == .success ? "checkmark" : record.run.state == .failure ? "xmark" : "minus")
                                        .font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.background)
                                }
                            }.frame(maxWidth: .infinity).frame(height: 24)
                    }.buttonStyle(HandButtonStyle())
                        .help("\(record.repository) · \(record.run.workflowName) · \(record.run.state.label)")
                        .accessibilityLabel("\(record.run.workflowName), \(record.run.state.label). Abrir ejecución")
                }
            }
        }.accessibilityElement(children: .contain)
    }
}
