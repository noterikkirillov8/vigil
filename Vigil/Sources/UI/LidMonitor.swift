import AppKit

@MainActor
final class LidMonitor: NSObject {
    private let running: () -> Bool, saveDisplay: () -> Void, endForHeat: () -> Void
    private lazy var clamshell = Clamshell { [weak self] in self?.sample() }
    private lazy var policy = LidGuard(readClosed: clamshell.read, readThermal: { ProcessInfo.processInfo.thermalState })
    private let mute = LidMute(audio: CoreOutput(), file: StateFile.standard.url.deletingLastPathComponent().appendingPathComponent("lid-mute.json"))
    private var deadline: Task<Void, Never>?
    private var stopWatching: (() -> Void)?
    private var stopWatchingDevices: (() -> Void)?
    private var restorePending = false

    init(running: @escaping () -> Bool, saveDisplay: @escaping () -> Void, endForHeat: @escaping () -> Void) {
        self.running = running; self.saveDisplay = saveDisplay; self.endForHeat = endForHeat
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(thermalChanged), name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(woke), name: NSWorkspace.didWakeNotification, object: nil)
        stopWatchingDevices = CoreOutput().watchDevices { [weak self] in
            guard let self, mute.record != nil else { return }
            stopWatching?(); stopWatching = nil
            sample()
        }
    }

    @objc nonisolated private func thermalChanged(_ note: Notification) { Task { @MainActor in sample() } }
    @objc nonisolated private func woke(_ note: Notification) { Task { @MainActor in sample(recovery: true) } }

    func sample(recovery: Bool = false) {
        deadline?.cancel(); deadline = nil
        let action = policy.sample(at: ProcessInfo.processInfo.systemUptime, running: running(), saver: Prefs.bool(Prefs.lidSaver),
                                   heat: Prefs.bool(Prefs.heatGuard), recovery: recovery)
        if action.restore || restorePending { mute.restore(); restorePending = mute.record != nil }
        if action.save { saveDisplay(); mute.save() }
        if let uid = mute.record?.uid, stopWatching == nil {
            stopWatching = CoreOutput().watchMute(uid) { [weak self] in
                guard let self else { return }
                mute.relinquishIfUnmuted()
                if mute.record == nil { stopWatching?(); stopWatching = nil }
            }
        } else if mute.record == nil { stopWatching?(); stopWatching = nil }
        if action.end { endForHeat(); return }
        if let remaining = action.remaining {
            deadline = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(remaining)) } catch { return }
                self?.sample()
            }
        }
    }

    func stop() {
        NotificationCenter.default.removeObserver(self); NSWorkspace.shared.notificationCenter.removeObserver(self)
        deadline?.cancel(); stopWatching?(); stopWatching = nil; stopWatchingDevices?(); stopWatchingDevices = nil; mute.restore()
    }
}
