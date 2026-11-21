import Foundation

/// The only two commands Vigil ever runs for lid mode. They match the sudoers rule, so `sudo -n` never asks for a password.
enum LidCommand {
    static let on = ["/usr/bin/sudo", "-n", "/usr/bin/pmset", "-a", "disablesleep", "1"]
    static let off = ["/usr/bin/sudo", "-n", "/usr/bin/pmset", "-a", "disablesleep", "0"]
    static let setup = #"echo "$USER ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0" | sudo tee /etc/sudoers.d/vigil && sudo chmod 440 /etc/sudoers.d/vigil"#
}

enum Watchdog {
    static let grace = 60
    /// Runs detached: waits for the app to die or the session to be a minute overdue, then restores sleep.
    static func script(appPid: Int32, end: Date) -> String {
        "while kill -0 \(appPid) 2>/dev/null && [ $(date +%s) -lt \(Int(end.timeIntervalSince1970) + grace) ]; do sleep 5; done; "
            + LidCommand.off.joined(separator: " ")
    }
}

/// Login agent: at login and every 5 min, if a lid session was left on and Vigil is not running, turn sleep back on.
/// Covers what the watchdog can't: a restart or crash that takes both down.
struct Backstop {
    static let label = "com.erikkirillov.Vigil.backstop"
    static func script(stateFile: String) -> String {
        let quoted = "'" + stateFile.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return "S=\(quoted); [ -f \"$S\" ] || exit 0; /usr/bin/pgrep -xq Vigil && exit 0; "
            + LidCommand.off.joined(separator: " ") + " && /bin/rm -f \"$S\""
    }
    static func plist(stateFile: String) -> [String: Any] {
        ["Label": label, "ProgramArguments": ["/bin/sh", "-c", script(stateFile: stateFile)], "RunAtLoad": true, "StartInterval": 300]
    }
}

/// Everything that changes power settings goes through this, so tests can use a fake.
protocol PowerControl {
    func sleepDisplay()
    func setLid(_ on: Bool) -> Bool
    func spawnWatchdog(script: String) -> Int32?
    func killWatchdog(_ pid: Int32)
}

protocol SafetyHelperInstaller {
    var isInstalled: Bool { get }
    func install(stateFile: URL)
}

protocol SleepAssertions {
    func hold(display: Bool)
    func release()
}

/// A small file that says "a lid session is active". Present at launch means the last run did not finish cleanly.
struct LidState: Codable, Equatable { var end: Date; var watchdogPid: Int32? }

struct StateFile {
    let url: URL
    static var standard: StateFile {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Vigil")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return StateFile(url: dir.appendingPathComponent("lid-session.json"))
    }
    var exists: Bool { FileManager.default.fileExists(atPath: url.path) }
    func write(_ s: LidState) { try? JSONEncoder().encode(s).write(to: url, options: .atomic) }
    func clear() { try? FileManager.default.removeItem(at: url) }   // our own state file, not user data
}

enum EndReason { case finished, battery }

/// Runs one session: assertions, lid mode, watchdog and state file. Every path out goes through `end()`.
@MainActor
final class SessionController {
    private let power: PowerControl
    private let assertions: SleepAssertions
    private let state: StateFile
    private let helper: SafetyHelperInstaller
    private let pid: Int32
    private(set) var session: Session?
    private(set) var lidActive = false
    private(set) var lidFailed = false
    private var watchdogPid: Int32?

    func sleepDisplay() { if session != nil { power.sleepDisplay() } }

    init(power: PowerControl, assertions: SleepAssertions, state: StateFile, helper: SafetyHelperInstaller, pid: Int32 = ProcessInfo.processInfo.processIdentifier) {
        self.helper = helper
        self.power = power; self.assertions = assertions; self.state = state; self.pid = pid
    }

    /// Launch: a state file means the last run died with lid mode on.
    func recoverOnLaunch() {
        guard state.exists else { return }
        if power.setLid(false) { state.clear() }
    }

    func start(length: TimeInterval, now: Date, lid: Bool, display: Bool) {
        start(Session(start: now, length: length), lid: lid, display: display)
    }

    func start(_ s: Session, lid: Bool, display: Bool) {
        guard session == nil else { return }
        session = s
        lidFailed = false
        assertions.hold(display: display)
        if lid { lidFailed = !enableLid(end: s.end) }
    }

    func add(_ seconds: TimeInterval, now: Date) {
        guard session != nil else { return }
        session?.add(seconds, now: now)
        if lidActive, let end = session?.end { arm(end: end) }
    }

    /// Returns the reason when the session just ended.
    func tick(now: Date, battery: BatteryState?, floor: Int) -> EndReason? {
        guard let s = session else { return nil }
        if s.isOver(now: now) { end(); return .finished }
        if let b = battery, Battery.floorHit(onBattery: b.onBattery, percent: b.percent, floor: floor) { end(); return .battery }
        return nil
    }

    /// Safe to call any number of times, from any path (End, Quit, terminate, timer).
    func end() {
        guard session != nil else { return }
        session = nil
        assertions.release()
        guard lidActive || state.exists else { return }
        lidActive = false
        if power.setLid(false) {   // on failure the watchdog and state file stay, so the next launch retries
            if let pid = watchdogPid { power.killWatchdog(pid) }
            watchdogPid = nil
            state.clear()
        } else if let new = power.spawnWatchdog(script: Watchdog.script(appPid: pid, end: Date())) {
            // Restore failed: a fresh watchdog retries within a minute instead of waiting for the old session end.
            if let old = watchdogPid { power.killWatchdog(old) }
            watchdogPid = new
            state.write(LidState(end: Date(), watchdogPid: new))
        }
    }

    private func enableLid(end: Date) -> Bool {
        arm(end: end)
        guard power.setLid(true) else {
            if let pid = watchdogPid { power.killWatchdog(pid) }
            watchdogPid = nil
            state.clear()
            return false
        }
        lidActive = true
        if !helper.isInstalled { helper.install(stateFile: state.url) }
        return true
    }

    /// (Re)spawns the watchdog for `end` and records it, always before lid mode is turned on.
    private func arm(end: Date) {
        if let old = watchdogPid { power.killWatchdog(old) }
        watchdogPid = power.spawnWatchdog(script: Watchdog.script(appPid: pid, end: end))
        state.write(LidState(end: end, watchdogPid: watchdogPid))
    }
}
