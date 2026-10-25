import ActionsWatcherCore
import AppKit
import SwiftUI

enum Theme {
    static let background = Color(hex: 0x010736)
    static let surface = Color(hex: 0x0D1C42)
    static let raised = Color(hex: 0x22396F)
    static let accent = Color(hex: 0xFCF1D0)
    static let border = accent.opacity(0.13)
    static let primary = accent
    static let secondary = accent.opacity(0.76)
    static let muted = accent.opacity(0.58)

    // Semantic colors distinguish workflow results from the navy-and-cream interface.
    static let success = Color(hex: 0xA4E8B4)
    static let warning = Color(hex: 0xE9C77C)
    static let failure = Color(hex: 0xF29393)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255,
                  green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }
}

extension RunState {
    var color: Color {
        switch self {
        case .running: Theme.accent
        case .success: Theme.success
        case .queued: Theme.warning
        case .failure: Theme.failure
        case .cancelled, .neutral: Theme.secondary
        }
    }
    var symbol: String {
        switch self {
        case .running: "circle.dotted.circle"
        case .queued: "clock"
        case .success: "checkmark.circle.fill"
        case .failure: "xmark.circle.fill"
        case .cancelled: "minus.circle"
        case .neutral: "circle.dashed"
        }
    }
}

struct StatusIcon: View {
    let state: RunState
    var size: CGFloat = 17
    var body: some View {
        ActivityGlyph(state: state, size: size)
    }
}

struct IconButton: View {
    let symbol: String
    let label: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.secondary).frame(width: 29, height: 29)
                .background(Theme.raised.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }.buttonStyle(HandButtonStyle()).help(label).accessibilityLabel(label)
    }
}

struct AccentButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.background).frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(Theme.accent.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 10))
            .handCursor()
    }
}

struct Surface: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(16).background(Theme.surface, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Theme.border, lineWidth: 1))
    }
}

extension View { func surface() -> some View { modifier(Surface()) } }

struct ErrorBanner: View {
    let message: String
    var dismiss: (() -> Void)?
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(Theme.warning)
            Text(message).font(.system(size: 11)).foregroundStyle(Theme.primary).fixedSize(horizontal: false, vertical: true)
            if let dismiss {
                Button(action: dismiss) { Image(systemName: "xmark").font(.system(size: 10)) }
                    .buttonStyle(HandButtonStyle()).foregroundStyle(Theme.secondary).accessibilityLabel("Cerrar aviso")
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct SectionLabel: View {
    let title: String
    var trailing: String?
    var body: some View {
        HStack {
            Text(title).tracking(1.6)
            Spacer()
            if let trailing { Text(trailing).monospacedDigit() }
        }.font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.muted)
    }
}

func openGitHub(_ url: URL) {
    guard url.scheme == "https", url.host == "github.com" else { return }
    NSWorkspace.shared.open(url)
}

func elapsed(_ run: WorkflowRun, now: Date = .now) -> String {
    let seconds = max(0, Int((run.state.isActive ? now : run.updatedAt).timeIntervalSince(run.startedAt)))
    if seconds >= 3600 { return "\(seconds / 3600) h \((seconds % 3600) / 60) min" }
    return seconds >= 60 ? "\(seconds / 60) min \(seconds % 60) s" : "\(seconds) s"
}
