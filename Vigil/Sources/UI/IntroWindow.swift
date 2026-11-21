import AppKit
import SwiftUI

/// The intro window: a normal centred window that fades in and out. No dim layers, no flying, no guessed
/// coordinates. Closing it by any means (Esc, Cmd-W, close button, Skip, Get started) calls `onClose` once.
@MainActor
final class IntroPresenter {
    private var window: IntroWindow?
    private var monitor: Any?
    private var closeObserver: NSObjectProtocol?
    private var closing = false
    var isShowing: Bool { window != nil && !closing }
    /// Called once per showing, before the fade-out starts, so the app never waits on the animation.
    var onClose: () -> Void = {}
    var onNext: () -> Void = {}
    var onBack: () -> Void = {}

    func focus() { NSApp.activate(); window?.makeKeyAndOrderFront(nil) }

    func show<V: View>(_ content: V, size: CGSize) {
        if let window, !closing { NSApp.activate(); window.makeKeyAndOrderFront(nil); return }
        closing = false
        let w = IntroWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.level = .floating
        w.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: content)
        host.sizingOptions = []
        w.contentView = host
        w.center()
        w.alphaValue = 0
        window = w
        // Esc and Cmd-W close, arrows and Return step. A monitor scoped to this window, so it needs no responder chain.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak w] e in
            guard let self, let w, e.window === w else { return e }
            switch (e.keyCode, e.modifierFlags.contains(.command)) {
            case (53, _), (13, true): self.close()
            case (124, false), (36, false), (76, false): self.onNext()
            case (123, false): self.onBack()
            default: return e
            }
            return nil
        }
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        NSApp.activate()
        w.makeKeyAndOrderFront(nil)
        fade(w, to: 1, 0.25) { }
    }

    /// Safe to call any number of times, from any close path.
    func close() {
        guard let w = window, !closing else { return }
        closing = true
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver); self.closeObserver = nil }
        w.level = .normal
        onClose()
        fade(w, to: 0, 0.2) { [weak self] in
            w.orderOut(nil)
            if self?.window === w { self?.window = nil }
        }
    }

    private func fade(_ w: NSWindow, to alpha: CGFloat, _ duration: Double, done: @escaping @MainActor () -> Void) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            w.animator().alphaValue = alpha
        } completionHandler: { MainActor.assumeIsolated { done() } }
    }
}

final class IntroWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}
