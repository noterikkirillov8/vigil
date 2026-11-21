import AppKit
import SwiftUI
import Observation
import ServiceManagement

enum Prefs {
    static let defaultMinutes = "vigilDefaultMinutes", lid = "vigilLid", display = "vigilDisplay", showTime = "vigilShowTime"
    static let away = "vigilAway", awayMinutes = "vigilAwayMinutes", keep = "vigilKeep", floor = "vigilFloor", tab = "vigilSettingsTab"
    static let accent = Color(hex: 0x9D8CFF)
    nonisolated(unsafe) static let store: UserDefaults = Demo.on ? Demo.store() : .standard
    static let followAgents = "vigilFollowAgents", sleepWhileWaiting = "vigilSleepWhileWaiting"
    static let lidSaver = "vigilLidSaver", heatGuard = "vigilHeatGuard"
    static let nightLast = "vigilNightLast", nightly = "vigilNightly", nightFrom = "vigilNightFrom", nightTo = "vigilNightTo"
    static let phonePings = "vigilPhonePings", phoneTopic = "vigilPhoneTopic", includeNames = "vigilIncludeProjectNames"

    static func register() {
        Prefs.store.register(defaults: [defaultMinutes: 120, lid: true, display: false, showTime: true, away: false,
                                                  awayMinutes: 30, floor: 10, keep: Away.defaultKeep, followAgents: false, sleepWhileWaiting: false,
                                                  lidSaver: true, heatGuard: true, nightly: false, nightFrom: 60, nightTo: 420])
    }
    static var keepList: [String] {
        get { Prefs.store.stringArray(forKey: keep) ?? Away.defaultKeep }
        set { Prefs.store.set(newValue, forKey: keep) }
    }
    static func bool(_ k: String) -> Bool { Prefs.store.bool(forKey: k) }
    static func int(_ k: String) -> Int { Prefs.store.integer(forKey: k) }
}

@MainActor
@Observable
final class VigilModel {
    var session: Session?
    var now = Date()
    var lidActive = false
    var followingAgents = false
    var lidFailed = false
    var safetyHelperInstalled = false
    var helperRemovalFailed = false
    var insomnia = false
    var selected: Int
    var custom = 90
    var shown = false
    var launchAtLogin = !Demo.on && SMAppService.mainApp.status == .enabled
    var isOpen = false { didSet { if isOpen != oldValue { reschedule() } } }

    @ObservationIgnored var onStatus: () -> Void = {}
    @ObservationIgnored var onShowIntro: () -> Void = {}
    @ObservationIgnored var onSettings: () -> Void = {}
    @ObservationIgnored var onHotKey: (KitHotKey?) -> Void = { _ in }
    @ObservationIgnored private let controller: SessionController?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var awayFired = false
    @ObservationIgnored private var lastMenuText: String?
    @ObservationIgnored private var agentPoll: Task<Void, Never>?
    @ObservationIgnored private var agentFollow = AgentFollow()
    @ObservationIgnored private var waitPings = WaitPings()
    @ObservationIgnored private var followedProjects: Set<String> = []
    @ObservationIgnored private let sendPing: (URLRequest) -> Void
    @ObservationIgnored private var lidMonitor: LidMonitor?
    @ObservationIgnored private var nightTimer: DispatchSourceTimer?

    /// `live: false` is for QA renders: no controller, so nothing can touch power settings.
    init(live: Bool = true, sendPing: @escaping (URLRequest) -> Void = { URLSession.shared.dataTask(with: $0).resume() }) {
        self.sendPing = Demo.on ? { _ in } : sendPing
        Prefs.register()
        let d = Prefs.int(Prefs.defaultMinutes)
        selected = Presets.minutes.contains(d) ? d : Presets.custom
        if !Presets.minutes.contains(d) { custom = Presets.snap(d) }
        controller = !live ? nil : Demo.on
            ? SessionController(power: DemoPower(), assertions: IOAssertions(), state: StateFile(url: FileManager.default.temporaryDirectory.appendingPathComponent("vigil-demo.json")), helper: DemoHelper())
            : SessionController(power: RealPower(), assertions: IOAssertions(), state: .standard, helper: Backstop())
        refreshSafetyHelper()
        controller?.recoverOnLaunch()
        if live && !Demo.on {
            lidMonitor = LidMonitor(running: { [weak self] in self?.running == true }, saveDisplay: { [weak self] in self?.controller?.sleepDisplay() },
                                    endForHeat: { [weak self] in self?.end(reason: .hot) })
            lidMonitor?.sample(recovery: true)
        }
        configureAgentPolling()
        configureNightSchedule()
    }

    var running: Bool { session != nil }

    /// Settings changed the default length: the idle panel follows it (a running session is untouched).
    func applyDefaultLength() {
        let d = Prefs.int(Prefs.defaultMinutes)
        guard !running else { return }
        if Presets.minutes.contains(d) { selected = d } else { custom = Presets.snap(d); selected = Presets.custom }
    }

    func start() {
        guard let c = controller, !running else { return }
        let minutes = selected == Presets.custom ? custom : selected
        awayFired = false
        c.start(length: Double(minutes * 60), now: Date(), lid: Prefs.bool(Prefs.lid), display: Prefs.bool(Prefs.display))
        refreshSafetyHelper()
        sync()
    }
    func add(minutes: Int) { guard !followingAgents else { return }; controller?.add(Double(minutes * 60), now: Date()); sync() }
    private func ping(_ event: PhonePing, projects: Set<String>) {
        guard controller != nil else { return }
        event.post(enabled: Prefs.bool(Prefs.phonePings), topic: Prefs.store.string(forKey: Prefs.phoneTopic) ?? "",
                   projects: projects, includeNames: Prefs.bool(Prefs.includeNames), send: sendPing)
    }

    private func pingEnd(_ reason: PhonePing) {
        if running { ping(reason, projects: followedProjects) }
        followedProjects.removeAll()
    }

    func end(reason: PhonePing = .ended) {
        if followingAgents { agentFollow.stop(); followingAgents = false }
        controller?.end(); pingEnd(reason); sync()
    }
    func toggle() { running ? end() : start() }
    /// Quit and terminate: always restore sleep first.
    func shutdown() { nightTimer?.cancel(); agentPoll?.cancel(); controller?.end(); pingEnd(.ended); lidMonitor?.stop() }

    func configureNightSchedule() {
        nightTimer?.cancel(); nightTimer = nil
        guard controller != nil, Prefs.bool(Prefs.nightly) else { return }
        let nextMinute = (Int(Date().timeIntervalSince1970) / 60 + 1) * 60
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(wallDeadline: DispatchWallTime(timespec: timespec(tv_sec: nextMinute, tv_nsec: 0)), repeating: .seconds(60))
        timer.setEventHandler { [weak self] in self?.startScheduledNight() }
        nightTimer = timer
        timer.resume()
    }

    private func startScheduledNight() {
        guard let controller, Prefs.bool(Prefs.nightly) else { return }
        let date = Date(), floor = Prefs.int(Prefs.floor)
        let schedule = NightSchedule(from: Prefs.int(Prefs.nightFrom), to: Prefs.int(Prefs.nightTo))
        let last = Prefs.store.object(forKey: Prefs.nightLast) as? Date
        guard let night = schedule.pending(at: date, calendar: .current, lastRun: last) else { return }
        Prefs.store.set(night.start, forKey: Prefs.nightLast)   // started or skipped, tonight is handled
        guard !schedule.skips(running: running, battery: Sys.battery(), floor: floor) else { return }
        awayFired = false
        controller.start(Session(start: date, scheduledEnd: night.end), lid: Prefs.bool(Prefs.lid), display: Prefs.bool(Prefs.display))
        refreshSafetyHelper(); sync()
    }

    func refreshLidGuard() { lidMonitor?.sample() }

    func configureAgentPolling() {
        guard controller != nil else { return }
        agentPoll?.cancel(); agentPoll = nil
        let follow = Prefs.bool(Prefs.followAgents), notify = Prefs.bool(Prefs.phonePings)
        if !notify { waitPings = WaitPings() }
        if !follow {
            if followingAgents { end() }
            agentFollow = AgentFollow()
        }
        guard follow || notify else { return }
        let began = Date()
        agentPoll = Task { [weak self] in
            while !Task.isCancelled {
                let next = ContinuousClock.now + .seconds(Demo.on ? 2 : 30)
                let activity = Demo.on ? Demo.agents(since: began) : await Task.detached(priority: .utility) { AgentProbe.sample(includeCodex: follow) }.value
                guard !Task.isCancelled, let self else { return }
                self.applyAgentActivity(activity)
                try? await Task.sleep(until: next, clock: .continuous)
            }
        }
    }

    private func applyAgentActivity(_ activity: AgentActivity) {
        let date = Date()
        if Prefs.bool(Prefs.phonePings) {
            for id in waitPings.due(activity, at: date) { ping(.waiting, projects: activity.waiterProjects[id].map { [$0] } ?? []) }
        }
        guard let controller, Prefs.bool(Prefs.followAgents), !running || followingAgents else { return }
        if followingAgents { followedProjects.formUnion(activity.workingProjects) }
        switch agentFollow.decide(activity, at: date, following: followingAgents, sleepWhileWaiting: Prefs.bool(Prefs.sleepWhileWaiting)) {
        case .start:
            let floor = Prefs.int(Prefs.floor)
            if floor > 0, let battery = Sys.battery(), Battery.floorHit(onBattery: battery.onBattery, percent: battery.percent, floor: floor) { return }
            followingAgents = true; awayFired = false
            followedProjects = activity.workingProjects
            controller.start(length: AgentFollow.cap, now: date, lid: Prefs.bool(Prefs.lid), display: Prefs.bool(Prefs.display))
            refreshSafetyHelper(); sync()
        case .end:
            followingAgents = false
            end(reason: activity.waiting.isEmpty && !activity.other && !activity.unavailable ? .finished : .ended)
        case .hold: break
        }
    }

    func refreshInsomnia() { insomnia = !Demo.on && !NSRunningApplication.runningApplications(withBundleIdentifier: "com.kgarg.insomnia").isEmpty }

    func refreshSafetyHelper() {
        if controller != nil, !Demo.on { safetyHelperInstalled = Backstop().isInstalled }
    }

    func removeSafetyHelper() {
        guard controller != nil, !lidActive, !Demo.on else { return }
        helperRemovalFailed = !Backstop().remove()
        refreshSafetyHelper()
    }

    func setLaunchAtLogin(_ on: Bool) {
        guard !Demo.on else { return }
        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch {}
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func sync() {
        guard let c = controller else { return }
        session = c.session; lidActive = c.lidActive; lidFailed = c.lidFailed; now = Date()
        lastMenuText = session.map { Session.menuText($0.remaining(now: now)) }
        refreshLidGuard()
        onStatus()
        reschedule()
    }

    private func reschedule() {
        timer?.invalidate(); timer = nil
        guard let s = session else { return }
        let iv = Ticker.interval(panelOpen: isOpen, showTime: Prefs.bool(Prefs.showTime), remaining: s.remaining(now: Date()))
        let t = Timer(timeInterval: iv, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
        t.tolerance = iv * 0.1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        guard let c = controller else { return }
        let floor = Prefs.int(Prefs.floor)
        if c.tick(now: Date(), battery: floor > 0 ? Sys.battery() : nil, floor: floor) != nil {
            pingEnd(.ended)
            if followingAgents { agentFollow.stop(); followingAgents = false }
            KitSound.play(.confirm)
            sync()
            return
        }
        if Prefs.bool(Prefs.away), !Demo.on { awayCheck() }
        now = Date()
        // The menu bar text only changes on a minute boundary: redraw only then.
        let text = session.map { Session.menuText($0.remaining(now: now)) }
        if text != lastMenuText { lastMenuText = text; onStatus() }
        reschedule()
    }

    /// Once per away period: ask regular apps outside the keep list to quit, like ⌘Q.
    private func awayCheck() {
        let minutes = Prefs.int(Prefs.awayMinutes), idle = Sys.idleSeconds()
        guard Away.isAway(idle: idle, minutes: minutes) else { awayFired = false; return }
        guard !awayFired else { return }
        awayFired = true
        let regular = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        let me = ProcessInfo.processInfo.processIdentifier
        let infos = regular.compactMap { a in a.localizedName.map { AppInfo(name: $0, pid: a.processIdentifier) } }
        for app in Away.select(running: infos, keep: Prefs.keepList, idle: idle, minutes: minutes, alreadyQuit: false, selfPid: me) {
            NSRunningApplication(processIdentifier: app.pid)?.terminate()
        }
    }

    /// QA only: a running session with `remaining` of `total` seconds left.
    func demo(remaining: TimeInterval, total: TimeInterval, lid: Bool = true) {
        let n = Date()
        session = Session(start: n.addingTimeInterval(-(total - remaining)), length: total)
        now = n; lidActive = lid
    }
}
