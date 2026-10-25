import AppKit
import SwiftUI

extension View {
    func handCursor() -> some View { modifier(HandCursorModifier()) }
}

private struct HandCursorModifier: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.pointerStyle(isEnabled ? .link : .default)
        } else {
            content.background(HandCursorRegion(isEnabled: isEnabled).allowsHitTesting(false))
        }
    }
}

/// Preserves the standard plain button behavior while adding its pointer affordance.
struct HandButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PlainButtonStyle().makeBody(configuration: configuration).handCursor()
    }
}

// macOS 14 uses AppKit cursor rectangles so scrolling, removal and window changes
// restore the cursor automatically, without a global push/pop cursor stack.
private struct HandCursorRegion: NSViewRepresentable {
    let isEnabled: Bool

    func makeNSView(context: Context) -> HandCursorView {
        let view = HandCursorView()
        view.isEnabled = isEnabled
        return view
    }

    func updateNSView(_ view: HandCursorView, context: Context) { view.isEnabled = isEnabled }
}

private final class HandCursorView: NSView {
    var isEnabled = true {
        didSet {
            if oldValue != isEnabled { window?.invalidateCursorRects(for: self) }
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if isEnabled, !visibleRect.isEmpty { addCursorRect(visibleRect, cursor: .pointingHand) }
    }
}
