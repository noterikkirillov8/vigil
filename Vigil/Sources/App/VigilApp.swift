import AppKit
import Carbon
import SwiftUI

/// One borderless panel for the app's whole life; opening it is just `orderFront`.
final class VigilPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    var onCancel: () -> Void = {}
    override func cancelOperation(_ sender: Any?) { onCancel() }   // the same close as a click outside, so state and the mouse monitor are cleaned up
}

@main
@MainActor
final class VigilApp: NSObject, NSApplicationDelegate {
    static func main() {
        if QA.renderHotspotIfAsked() { return }
        if QA.renderPhoneIfAsked() { return }
        if QA.renderNightIfAsked() { return }
        if QA.renderLidIfAsked() { return }
        if QA.renderAgentsIfAsked() { return }
        if QA.renderStatusIfAsked() { return }
        if QA.renderDemoIfAsked() { return }
        let app = NSApplication.shared
        let delegate = VigilApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    private lazy var model = VigilModel()
    private var statusItem: NSStatusItem!
    private var panel: VigilPanel!
    private var host: NSHostingView<VigilView>!
    private var monitor: Any?
    private var menuOpen = false
    private var lastResignClose = Date.distantPast
    private var closing: DispatchWorkItem?
    private let intro = IntroController()
    private lazy var settings = SettingsController(model: model)

    func applicationDidFinishLaunching(_ notification: Notification) {
        if QA.runIfAsked() || IntroPreview.runIfAsked() { return }
        _ = model   // recovers a lid session left by a crash before anything else
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = StatusImage.make(.idle)
            button.target = self
            button.action = #selector(toggle)
        }
        model.onStatus = { [weak self] in self?.updateStatus() }
        makePanel()
        let register = { (k: KitHotKey?) in
            guard let k else { HotKeys.shared.unregister(1); return }
            HotKeys.shared.register(1, HotKeyPref.carbon(k)) { [weak self] in self?.model.toggle() }
        }
        register(HotKeyPref.load())
        model.onHotKey = register
        model.onSettings = { [weak self] in self?.hide(); self?.settings.show() }
        model.onShowIntro = { [weak self] in self?.hide(); self?.intro.show() }
        if !IntroController.seen { DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in MainActor.assumeIsolated { self?.hide(); self?.intro.show() } } }
    }

    /// Every quit path ends here: sleep settings are restored before the process goes.
    func applicationWillTerminate(_ notification: Notification) { if statusItem != nil { model.shutdown() } }

    private func updateStatus() {
        guard let button = statusItem.button else { return }
        button.image = StatusImage.make(StatusMark(session: model.session, lidFailed: model.lidFailed))
        if let s = model.session, !model.followingAgents, Prefs.bool(Prefs.showTime) {
            button.attributedTitle = StatusImage.title(Session.menuText(s.remaining(now: Date())))
            button.imagePosition = .imageLeft
        } else {
            button.title = ""
            button.imagePosition = .imageOnly
        }
    }

    private func makePanel() {
        panel = VigilPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 220),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.onCancel = { [weak self] in self?.hide() }
        host = NSHostingView(rootView: VigilView(model: model, onHeight: { [weak self] h in self?.resize(to: h) }))
        host.sizingOptions = []
        panel.contentView = host
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.panel.isVisible, self.model.shown, !self.menuOpen else { return }
                self.lastResignClose = Date()
                self.hide()
            }
        }
        host.frame = NSRect(x: 0, y: 0, width: 340, height: 300)
        host.layoutSubtreeIfNeeded()
    }

    /// The panel keeps its top edge and resizes in one 0.28 s ease-out, in step with the content.
    private func resize(to height: CGFloat) {
        guard height > 1, let panel else { return }
        var f = panel.frame
        guard abs(f.height - height) > 0.5 else { return }
        f.origin.y += f.height - height
        f.size.height = height
        if !panel.isVisible || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.setFrame(f, display: false)
        } else {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.28
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                ctx.allowsImplicitAnimation = true
                panel.animator().setFrame(f, display: true)
            }
        }
        panel.invalidateShadow()
    }

    @objc private func toggle() {
        if intro.isShowing { hide(); intro.show(); return }
        if panel.isVisible && model.shown { hide(); return }
        if Date().timeIntervalSince(lastResignClose) < 0.25 { return }
        show()
    }

    private func show() {
        guard let button = statusItem.button, let bw = button.window else { return }
        model.isOpen = true
        model.refreshInsomnia()
        let b = bw.frame
        let vis = (bw.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let size = panel.frame.size
        let x = min(max(b.midX - size.width / 2, vis.minX + 8), vis.maxX - size.width - 8)
        panel.setFrameOrigin(NSPoint(x: x, y: b.minY - 6 - size.height))
        closing?.cancel()
        panel.orderFrontRegardless()
        panel.makeKey()
        model.shown = true
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    private func hide() {
        model.shown = false
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.panel.orderOut(nil) } }
        closing = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14, execute: work)
        model.isOpen = false
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
    }
}
