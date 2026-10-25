import ActionsWatcherCore
import AppKit
import Combine
import SwiftUI
import UserNotifications

@main
struct ActionsWatcherApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, UNUserNotificationCenterDelegate {
    private var store: MonitorStore!
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var subscriptions = Set<AnyCancellable>()
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = ProcessInfo.processInfo.arguments
        let preview = arguments.firstIndex(of: "--preview")
        store = MonitorStore(demo: arguments.contains("--demo") || preview != nil)
        if let preview, arguments.indices.contains(preview + 1) {
            renderPreviews(to: URL(fileURLWithPath: arguments[preview + 1], isDirectory: true))
            NSApplication.shared.terminate(nil)
            return
        }
        UNUserNotificationCenter.current().delegate = self
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = NSSize(width: 460, height: 670)
        popover.contentViewController = NSHostingController(rootView: RootView(store: store))
        store.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.updateStatusItem() }
        }.store(in: &subscriptions)
        updateStatusItem()
        let center = NSWorkspace.shared.notificationCenter
        sleepObserver = center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.store.setSuspended(true) }
        }
        wakeObserver = center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.store.setSuspended(false); await self?.store.refresh() }
        }
        if store.isDemo { showPopover() }
        else {
            Task {
                await store.restoreSession()
                if !store.isConnected { showPopover() }
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showPopover(); return true }

    @objc private func togglePopover() {
        if NSApplication.shared.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Abrir ActionsWatcher", action: #selector(showFromMenu), keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(withTitle: "Salir", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            menu.items.first?.target = self
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else if popover.isShown { popover.performClose(nil) }
        else { showPopover() }
    }

    @objc private func showFromMenu() { showPopover() }

    private func showPopover() {
        guard let button = statusItem?.button else { return }
        NSApplication.shared.activate(ignoringOtherApps: true)
        store.isPanelVisible = true
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        Task { await store.refresh(); await store.updateNotificationStatus() }
    }

    func popoverDidClose(_ notification: Notification) { store.isPanelVisible = false }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let hasError = store.errorMessage != nil || !store.repositoryErrors.isEmpty
        let symbol = hasError ? "exclamationmark.circle" : store.isConnected ? store.summary.symbol : "arrow.triangle.branch"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "ActionsWatcher")
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageLeading
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        button.title = store.activeCount > 0 ? " \(store.activeCount)" : ""
        button.toolTip = hasError ? "ActionsWatcher · Sincronización pendiente" : "ActionsWatcher · \(store.isConnected ? store.summary.label : "Conectar GitHub")"
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound] }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse) async {
        guard let rawURL = response.notification.request.content.userInfo["url"] as? String,
              let url = URL(string: rawURL) else { return }
        await MainActor.run { openGitHub(url) }
    }

    private func renderPreviews(to directory: URL) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let scenes: [(String, AppScreen)] = [("dashboard", .dashboard), ("repositories", .repositories), ("settings", .settings), ("onboarding", .onboarding)]
            for (name, screen) in scenes {
                if screen == .onboarding {
                    try render(RootView(store: MonitorStore()), to: directory.appendingPathComponent("\(name).png"))
                } else {
                    store.screen = screen
                    try render(RootView(store: store), to: directory.appendingPathComponent("\(name).png"))
                }
            }
            store.enterDemo()
            store.selectedRun = store.records.first
            store.jobs = DemoContent.jobs
            try render(RootView(store: store), to: directory.appendingPathComponent("detail.png"))
            if let job = JobFocus.preferred(in: store.jobs) {
                try render(
                    VStack(alignment: .leading, spacing: 20) {
                        SectionLabel(title: "EXPLORAR JOB")
                        JobInspector(job: job)
                        Spacer(minLength: 0)
                    }.padding(22).frame(width: 460, height: 670, alignment: .topLeading)
                        .background(Theme.background).foregroundStyle(Theme.primary).preferredColorScheme(.dark).tint(Theme.accent),
                    to: directory.appendingPathComponent("job-inspector.png"))
            }
            store.selectedRun = store.records.first { $0.run.state == .failure }
            store.jobs = DemoContent.failedJobs
            try render(RootView(store: store), to: directory.appendingPathComponent("detail-failure.png"))
            store.selectedRun = store.records.first { $0.run.state == .queued }
            store.jobs = []
            try render(RootView(store: store), to: directory.appendingPathComponent("detail-waiting.png"))

            let motionProbe = ActivityGlyph(state: .running, size: 60, reduceMotionOverride: false)
                .frame(width: 460, height: 670).background(Theme.background)
                .environment(\.panelIsActive, true)
            try render(motionProbe, to: directory.appendingPathComponent("motion-1.png"),
                additionalFrame: directory.appendingPathComponent("motion-2.png"))
            let reducedMotionProbe = ActivityGlyph(state: .running, size: 60, reduceMotionOverride: true)
                .frame(width: 460, height: 670).background(Theme.background).environment(\.panelIsActive, true)
            try render(reducedMotionProbe,
                to: directory.appendingPathComponent("reduced-motion-1.png"),
                additionalFrame: directory.appendingPathComponent("reduced-motion-2.png"))
            let pausedMotionProbe = ActivityGlyph(state: .running, size: 60, reduceMotionOverride: false)
                .frame(width: 460, height: 670).background(Theme.background).environment(\.panelIsActive, false)
            try render(pausedMotionProbe,
                to: directory.appendingPathComponent("paused-motion-1.png"),
                additionalFrame: directory.appendingPathComponent("paused-motion-2.png"))
        } catch {
            FileHandle.standardError.write(Data("Preview error: \(error.localizedDescription)\n".utf8))
        }
    }

    private func render<V: View>(_ view: V, to url: URL, additionalFrame: URL? = nil) throws {
        // Render through AppKit so native text fields, scroll views and switches are included.
        let host = NSHostingView(rootView: view)
        let bounds = NSRect(x: 0, y: 0, width: 460, height: 670)
        let window = NSWindow(contentRect: bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.frame = bounds
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: .now.addingTimeInterval(0.15))
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        func capture(to destination: URL) throws {
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: bounds) else { throw GitHubError.invalidResponse }
            host.cacheDisplay(in: bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else { throw GitHubError.invalidResponse }
            try data.write(to: destination)
        }
        try capture(to: url)
        if let additionalFrame {
            RunLoop.current.run(until: .now.addingTimeInterval(0.45))
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            try capture(to: additionalFrame)
        }
        window.close()
    }
}
