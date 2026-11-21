import Foundation

/// Records every call instead of touching power settings. Nothing in the tests can run pmset.
final class FakePower: PowerControl {
    func sleepDisplay() { log.append("display-off") }
    var log: [String] = []
    var lidOK = true
    var nextPid: Int32 = 900
    func setLid(_ on: Bool) -> Bool { log.append(on ? "lid-on" : "lid-off"); return lidOK }
    func spawnWatchdog(script: String) -> Int32? { log.append("spawn:\(script)"); nextPid += 1; return nextPid }
    func killWatchdog(_ pid: Int32) { log.append("kill:\(pid)") }
}
final class FakeInstaller: SafetyHelperInstaller {
    var installs: [URL] = []
    var isInstalled: Bool { !installs.isEmpty }
    func install(stateFile: URL) { installs.append(stateFile) }
}
final class FakeAssertions: SleepAssertions {
    var held = false, display = false
    func hold(display: Bool) { held = true; self.display = display }
    func release() { held = false }
}

@main @MainActor
struct CoreTests {
    static var failures = 0
    static func check(_ ok: Bool, _ name: String) {
        print(ok ? "PASS \(name)" : "FAIL \(name)")
        if !ok { failures += 1 }
    }

    static func main() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        agentChecks(t0)
        phoneChecks(t0)
        nightChecks()
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("vigil-test-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        lidChecks(tmp)

        // session clock
        var s = Session(start: t0, length: 7200)
        check(s.remaining(now: t0) == 7200 && s.total == 7200, "session: starts at its length")
        check(s.remaining(now: t0.addingTimeInterval(7300)) == 0 && s.isOver(now: t0.addingTimeInterval(7200)), "session: over at the end, never negative")
        s.add(1800, now: t0.addingTimeInterval(600))
        check(s.remaining(now: t0.addingTimeInterval(600)) == 7200 - 600 + 1800, "session: +30 min adds to the end")
        var big = Session(start: t0, length: 100 * 3600)
        check(big.total == 24 * 3600, "session: length capped at 24 h")
        big.add(3600, now: t0.addingTimeInterval(3600))
        check(big.remaining(now: t0.addingTimeInterval(3600)) == 24 * 3600, "session: adding never goes past 24 h from now")
        check(Session.countdown(6127) == "1:42:07" && Session.countdown(7200) == "2:00:00", "text: countdown over an hour")
        check(Session.countdown(752.4) == "12:33" && Session.countdown(9) == "0:09" && Session.countdown(0) == "0:00", "text: countdown under an hour rounds up")
        check(Session.menuText(6127) == "1:42" && Session.menuText(3600) == "1:00" && Session.menuText(2520) == "42m" && Session.menuText(30) == "1m", "text: menu bar time")
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        let at = Date(timeIntervalSince1970: 1_800_000_000 + 0)   // 2027-01-15 08:00 UTC
        check(Session.endsAt(at.addingTimeInterval(34 * 60), calendar: utc) == "Ends at 08:34", "text: ends-at")
        check(Session.litSegments(remaining: 7200, total: 7200) == 24 && Session.litSegments(remaining: 3600, total: 7200) == 12
              && Session.litSegments(remaining: 1, total: 7200) == 1 && Session.litSegments(remaining: 0, total: 7200) == 0, "strip: lit segments follow time left")

        // presets
        check(Presets.label(30) == "30 min" && Presets.label(120) == "2 h" && Presets.label(Presets.custom) == "Custom", "presets: labels")
        check(Presets.snap(20) == 15 && Presets.snap(23) == 30 && Presets.snap(5) == 15 && Presets.snap(9999) == 1440, "presets: custom snaps to 15 min, 15 min to 24 h")
        check(Presets.long(135) == "2 h 15 min" && Presets.long(45) == "45 min" && Presets.long(1440) == "24 h", "presets: long text")
        check(Ticker.interval(visible: true, remaining: 500) == 1 && Ticker.interval(visible: false, remaining: 500) == 15
              && Ticker.interval(visible: false, remaining: 4) == 4 && Ticker.interval(visible: false, remaining: 0.2) == 1, "ticker: 1 s when visible, coarse but never late otherwise")

        // exact commands
        check(LidCommand.on == ["/usr/bin/sudo", "-n", "/usr/bin/pmset", "-a", "disablesleep", "1"], "lid: exact argv on")
        check(LidCommand.off == ["/usr/bin/sudo", "-n", "/usr/bin/pmset", "-a", "disablesleep", "0"], "lid: exact argv off")
        check(LidCommand.setup == #"echo "$USER ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0" | sudo tee /etc/sudoers.d/vigil && sudo chmod 440 /etc/sudoers.d/vigil"#, "lid: setup command text")

        // watchdog script
        let script = Watchdog.script(appPid: 4242, end: Date(timeIntervalSince1970: 1_800_003_600))
        check(script == "while kill -0 4242 2>/dev/null && [ $(date +%s) -lt 1800003660 ]; do sleep 5; done; /usr/bin/sudo -n /usr/bin/pmset -a disablesleep 0", "watchdog: exact script text")

        // backstop login agent
        let bs = Backstop.script(stateFile: "/Users/a b/it's/lid-session.json")
        check(bs == #"S='/Users/a b/it'\''s/lid-session.json'; [ -f "$S" ] || exit 0; /usr/bin/pgrep -xq Vigil && exit 0; /usr/bin/sudo -n /usr/bin/pmset -a disablesleep 0 && /bin/rm -f "$S""#, "backstop: exact script text, path quoted")
        let pl = Backstop.plist(stateFile: "/x")
        check(pl["RunAtLoad"] as? Bool == true && pl["StartInterval"] as? Int == 300 && (pl["ProgramArguments"] as? [String])?.first == "/bin/sh", "backstop: runs at login and every 5 min")

        // controller
        func make(_ name: String, helper: FakeInstaller = FakeInstaller()) -> (SessionController, FakePower, FakeAssertions, StateFile) {
            let p = FakePower(), a = FakeAssertions(), f = StateFile(url: tmp.appendingPathComponent(name))
            return (SessionController(power: p, assertions: a, state: f, helper: helper, pid: 4242), p, a, f)
        }
        let helper = FakeInstaller()
        let (first, power, _, state) = make("helper.json", helper: helper)
        first.recoverOnLaunch()
        first.start(length: 60, now: t0, lid: false, display: false); first.end()
        power.lidOK = false
        first.start(length: 60, now: t0, lid: true, display: false); first.end()
        check(helper.installs.isEmpty, "helper: no install on launch, ordinary start, or failed lid start")
        power.lidOK = true
        first.start(length: 60, now: t0, lid: true, display: false)
        check(helper.installs == [state.url], "helper: installs on the first successful lid start")
        first.end(); first.start(length: 60, now: t0, lid: true, display: false); first.end()
        let (relaunch, _, _, _) = make("helper.json", helper: helper)
        relaunch.start(length: 60, now: t0, lid: true, display: false); relaunch.end()
        check(helper.installs == [state.url], "helper: later lid starts and relaunch do not reinstall")
        var (c, p, a, f) = make("a.json")
        c.start(length: 3600, now: t0, lid: true, display: false)
        check(c.session != nil && c.lidActive && !c.lidFailed && a.held && !a.display, "start: session, lid and assertion on")
        check(p.log.count == 2 && p.log[0].hasPrefix("spawn:") && p.log[1] == "lid-on", "start: watchdog is spawned before lid mode turns on")
        check(f.exists, "start: state file written")
        c.add(1800, now: t0.addingTimeInterval(10))
        check(p.log.suffix(2).first == "kill:901" && p.log.last!.hasPrefix("spawn:") && p.log.last!.contains("\(Int(t0.timeIntervalSince1970) + 3600 + 1800 + 60)"), "add time: old watchdog killed, new one for the new end")
        check(c.tick(now: t0.addingTimeInterval(100), battery: BatteryState(onBattery: true, percent: 50), floor: 10) == nil, "tick: nothing happens mid-session")
        check(c.tick(now: t0.addingTimeInterval(5401), battery: nil, floor: 10) == .finished && c.session == nil, "tick: ends at the end time")
        check(p.log.suffix(2) == ["lid-off", "kill:902"] && !f.exists && !a.held && !c.lidActive, "end: lid off, watchdog killed, state cleared, assertion released")
        let n = p.log.count; c.end(); c.end()
        check(p.log.count == n, "end: a second end does nothing")

        (c, p, a, f) = make("b.json")
        c.start(length: 3600, now: t0, lid: true, display: true)
        check(a.display, "start: display assertion only when asked")
        check(c.tick(now: t0.addingTimeInterval(10), battery: BatteryState(onBattery: true, percent: 9), floor: 10) == .battery && c.session == nil, "tick: battery floor ends the session")

        (c, p, a, f) = make("c.json")
        p.lidOK = false
        c.start(length: 3600, now: t0, lid: true, display: false)
        check(c.session != nil && !c.lidActive && c.lidFailed && a.held && !f.exists, "no sudo rule: session runs without lid mode, flag set, state cleaned")
        check(p.log.contains("kill:901"), "no sudo rule: the watchdog is killed again")
        check(StatusMark(session: c.session, lidFailed: c.lidFailed) == .lidWarning, "status image: failed lid request shows warning")
        c.end()
        check(StatusMark(session: c.session, lidFailed: c.lidFailed) == .idle, "status image: ending the failed session clears warning")
        check(!p.log.contains("lid-off"), "no sudo rule: nothing to restore, no pmset call")

        (c, p, a, f) = make("d.json")
        c.start(length: 3600, now: t0, lid: false, display: false)
        check(p.log.isEmpty && c.session != nil && !f.exists, "lid setting off: no pmset, no watchdog")
        check(StatusMark(session: c.session, lidFailed: c.lidFailed) == .running, "status image: lid mode off is not a failure")
        c.end()
        check(p.log.isEmpty, "lid setting off: end touches nothing")

        (c, p, a, f) = make("e.json")
        c.start(length: 3600, now: t0, lid: true, display: false)
        p.lidOK = false
        c.end()
        check(f.exists && !p.log.contains("kill:901") && c.session == nil, "restore fails: state file and watchdog stay for the next try")

        // crash recovery
        (c, p, a, f) = make("f.json")
        f.write(LidState(end: t0, watchdogPid: 77))
        c.recoverOnLaunch()
        check(p.log == ["lid-off"] && !f.exists, "recovery: state file present means restore and clear")
        c.recoverOnLaunch()
        check(p.log == ["lid-off"], "recovery: no state file, nothing runs")
        (c, p, a, f) = make("g.json")
        f.write(LidState(end: t0, watchdogPid: nil)); p.lidOK = false
        c.recoverOnLaunch()
        check(f.exists, "recovery: failed restore keeps the file")
        try? "garbage".write(to: tmp.appendingPathComponent("h.json"), atomically: true, encoding: .utf8)
        (c, p, a, f) = make("h.json")
        c.recoverOnLaunch()
        check(p.log == ["lid-off"] && !f.exists, "recovery: an unreadable file still triggers a restore")
        let st = LidState(end: t0, watchdogPid: 5)
        check((try? JSONDecoder().decode(LidState.self, from: JSONEncoder().encode(st))) == st, "state file round trip")

        // battery floor
        check(Battery.floorHit(onBattery: true, percent: 10, floor: 10) && Battery.floorHit(onBattery: true, percent: 3, floor: 10), "battery: at or below the floor on battery")
        check(!Battery.floorHit(onBattery: true, percent: 11, floor: 10) && !Battery.floorHit(onBattery: false, percent: 2, floor: 10) && !Battery.floorHit(onBattery: true, percent: 1, floor: 0), "battery: above, plugged in, or off")

        // away
        let apps = [AppInfo(name: "Safari", pid: 1), AppInfo(name: "Claude", pid: 2), AppInfo(name: "Finder", pid: 3), AppInfo(name: "vigil", pid: 4), AppInfo(name: "Notes", pid: 5), AppInfo(name: "Mail", pid: 6)]
        let keep = ["claude", "Finder"]
        check(Away.select(running: apps, keep: keep, idle: 1800, minutes: 30, alreadyQuit: false, selfPid: 6).map(\.name) == ["Safari", "Notes"], "away: quits regular apps, not the keep list (any case), Vigil or itself")
        check(Away.select(running: apps, keep: keep, idle: 1799, minutes: 30, alreadyQuit: false, selfPid: 6).isEmpty, "away: not before the idle time")
        check(Away.select(running: apps, keep: keep, idle: 9000, minutes: 30, alreadyQuit: true, selfPid: 6).isEmpty, "away: once per away period")
        let other = AppInfo(name: "Demo Clock", pid: 7)
        check(Away.select(running: apps + [other], keep: Away.defaultKeep, idle: 9000, minutes: 30, alreadyQuit: false, selfPid: 6) == [other], "away: default keeps Safari and Notes but not an unlisted app")
        check(Set(Away.defaultKeep) == [
            "Claude", "Codex", "Terminal", "iTerm2", "Ghostty", "Warp", "Tailscale", "Ollama", "Finder",
            "Xcode", "Visual Studio Code", "Cursor", "Zed", "Sublime Text", "Nova",
            "Safari", "Google Chrome", "Brave Browser", "Arc", "Firefox",
            "Notes", "Mail", "Messages", "Pages", "Numbers", "Keynote"
        ], "away: default keep list includes the original nine apps and all 17 additions")

        // system readers do not crash
        _ = Sys.battery(); check(Sys.idleSeconds() >= 0, "system: idle time and battery readable")

        introFlowChecks { check($0, $1) }
        print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    static func nightChecks() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let iso = ISO8601DateFormatter()
        func date(_ text: String) -> Date { iso.date(from: text)! }
        let night = NightSchedule(from: 22 * 60, to: 7 * 60)
        func end(_ start: String, _ schedule: NightSchedule = night, running: Bool = false, battery: BatteryState? = nil) -> Date? {
            schedule.endIfDue(at: date(start), calendar: calendar, running: running, battery: battery, floor: 10)
        }
        let start = "2026-01-16T03:00:00Z", morning = date("2026-01-16T12:00:00Z")
        check(end(start) == morning && end("2026-01-16T03:00:12Z") == morning, "night: crosses midnight and keeps the exact local deadline")
        check(end("2026-01-16T02:59:59Z") == nil && end("2026-01-16T03:01:00Z") == nil, "night: no early start or catch-up after From")
        check(end(start, running: true) == nil && end(start, battery: BatteryState(onBattery: true, percent: 10)) == nil
              && end(start, battery: BatteryState(onBattery: false, percent: 8)) == morning, "night: skips busy and low-battery starts, allows AC")
        check(end(start, NightSchedule(from: 1320, to: 1320)) == nil, "night: equal times do not start a session")
        let usual = NightSchedule(from: 60, to: 420)
        check(end("2026-03-08T06:00:00Z", usual) == date("2026-03-08T11:00:00Z"), "night: spring forward keeps 07:00 after five elapsed hours")
        check(end("2026-03-08T07:00:00Z", NightSchedule(from: 150, to: 420)) == date("2026-03-08T11:00:00Z"), "night: missing 02:30 starts at 03:00")
        check(end("2026-11-01T05:00:00Z", usual) == date("2026-11-01T12:00:00Z") && end("2026-11-01T06:00:00Z", usual) == nil,
              "night: fall back starts only on the first 01:00")
        let longStart = "2026-10-31T11:15:00Z", longEnd = date("2026-11-01T12:00:00Z")
        let scheduled = end(longStart, NightSchedule(from: 435, to: 420)).map { Session(start: date(longStart), scheduledEnd: $0) }
        check(scheduled?.end == longEnd && scheduled?.total == 24.75 * 3600, "night: long fall-back night is not truncated to 24 hours")
    }

    static func lidChecks(_ directory: URL) {
        var closed: Bool? = false, thermal = ProcessInfo.ThermalState.serious
        var policy = LidGuard(readClosed: { closed }, readThermal: { thermal })
        func sample(_ seconds: Double, running: Bool = true, saver: Bool = true, heat: Bool = true, wake: Bool = false) -> LidGuard.Action {
            policy.sample(at: seconds, running: running, saver: saver, heat: heat, recovery: wake)
        }
        check(sample(0, wake: true).restore, "lid: recover on launch")
        closed = true
        check(sample(1).save && !sample(2).save, "lid: save exactly once on close")
        thermal = .critical
        check(!sample(120).end && sample(121).end, "heat: two continuous minutes across serious and critical")
        thermal = .fair
        check(sample(122).remaining == nil, "heat: cooling cancels deadline")
        thermal = .serious
        check(sample(123).remaining == 120 && sample(130, wake: true).restore && sample(131).remaining == 119, "heat: wake restores mute and starts a fresh interval")
        closed = false
        check(sample(140).restore && sample(260).remaining == nil, "heat: open lid cancels deadline")
        closed = true
        check(!sample(300, running: false).save && sample(301, running: false).remaining == nil, "lid: idle close has no effect")
        check(sample(302).remaining == 120 && sample(303, heat: false).remaining == nil, "heat: independent switch cancels deadline")
        closed = nil
        check(sample(400).remaining == nil, "heat: unknown lid state never ends a session")
        closed = false; _ = sample(401); closed = true
        check(!sample(402, saver: false).save && sample(403, saver: false).remaining == 119, "lid: saver off leaves heat protection active")

        final class Audio: OutputMute {
            var current = "speaker", devices = ["speaker": false, "headset": true], writable = true
            func defaultUID() -> String? { current }
            func muted(_ uid: String) -> Bool? { devices[uid] }
            func setMuted(_ muted: Bool, uid: String) -> Bool {
                guard writable else { return false }; devices[uid] = muted; return true
            }
        }
        let audio = Audio(), file = directory.appendingPathComponent("mute.json"), mute = LidMute(audio: audio, file: file)
        mute.save(); audio.current = "headset"; mute.save()
        check(mute.record == MuteRecord(uid: "speaker", previouslyMuted: false) && audio.devices["speaker"] == true, "mute: persist only the output changed by us")
        audio.devices["speaker"] = nil; mute.restore()
        check(mute.record != nil && audio.devices["headset"] == true, "mute: detached device never redirects restore")
        audio.devices["speaker"] = true; audio.writable = false; mute.restore(); audio.writable = true
        check(mute.record != nil && audio.devices["speaker"] == true, "mute: retain restore record until original output is writable")
        audio.devices["speaker"] = true; LidMute(audio: audio, file: file).restore()
        check(mute.record == nil && audio.devices == ["speaker": false, "headset": true], "mute: restart restores only the recorded UID")
        mute.save(); mute.restore()
        check(mute.record == nil && audio.devices["headset"] == true, "mute: previously muted output stays muted")
        audio.current = "speaker"; audio.writable = false; mute.save()
        check(mute.record == nil, "mute: failed write confers no ownership")
        audio.writable = true; mute.save(); audio.devices["speaker"] = false; mute.relinquishIfUnmuted(); audio.devices["speaker"] = true; mute.restore()
        check(mute.record == nil && audio.devices["speaker"] == true, "mute: manual unmute releases ownership even after remute")

        var requests: [URLRequest] = []
        let topic = "vigil-0123456789abcdef"
        PhonePing.hot.post(enabled: false, topic: topic) { requests.append($0) }
        PhonePing.hot.post(enabled: true, topic: "") { requests.append($0) }
        PhonePing.hot.post(enabled: true, topic: topic) { requests.append($0) }
        check(requests.count == 1 && requests.first?.httpMethod == "POST" && requests.first?.url?.lastPathComponent == topic, "heat: ping only a configured phone (fake sender)")
    }

    static func phoneChecks(_ origin: Date) {
        let topic = PhonePing.newTopic()
        check(PhonePing.link(topic)?.absoluteString == "https://ntfy.sh/" + topic && topic.count == 22 && topic != PhonePing.newTopic(), "phone: random 16-character topic and subscription link")
        let projects: Set<String> = ["/demo/Orchard"]
        var requests: [URLRequest] = []
        for event in PhonePing.allCases {
            event.post(enabled: true, topic: topic, projects: projects) { requests.append($0) }
        }
        let bodies = requests.compactMap { $0.httpBody.flatMap { String(data: $0, encoding: .utf8) } }
        check(bodies == ["Vigil session ended.", "Agents finished. Vigil ended the session.", "Mac too hot. Vigil ended the session.", "An agent has been waiting for you for over 15 min."], "phone: all four messages omit project names by default (fake sender)")
        check(requests.allSatisfy { $0.url == PhonePing.link(topic) && $0.httpMethod == "POST" && $0.timeoutInterval == 5 }, "phone: plain POST to the topic with a five-second timeout")
        check(PhonePing.waiting.message(projects: projects, includeNames: true) == PhonePing.waiting.rawValue + " Orchard", "phone: opt-in adds only the project name")
        PhonePing.ended.post(enabled: true, topic: "../other") { requests.append($0) }
        check(requests.count == 4, "phone: invalid topic never reaches sender")

        let first = AgentActivity.claude(Data(#"[{"kind":"interactive","id":"a","status":"waiting","cwd":"/demo/Orchard"},{"kind":"background","id":"b","state":"blocked"}]"#.utf8))!
        var both = first; both.phoneWaiters.insert("b")
        var timer = WaitPings()
        func due(_ sample: AgentActivity, _ seconds: Double) -> Set<String> { timer.due(sample, at: origin.addingTimeInterval(seconds)) }
        check(first.phoneWaiters == ["a"] && first.waiterProjects["a"] == "Orchard", "phone: only Claude waiting status qualifies, never background blocked")
        check(due(first, 0).isEmpty && due(both, 900).isEmpty && due(both, 901) == ["a"] && due(both, 1801) == ["b"], "phone: independent waits ping once after more than fifteen minutes")
        check(due(AgentActivity(unavailable: true), 1810).isEmpty && due(both, 2800).isEmpty && due(both, 3800).isEmpty, "phone: failed poll never repeats a notified wait")
        check(due(AgentActivity(), 3801).isEmpty && due(first, 3810).isEmpty && due(first, 4711) == ["a"], "phone: leaving waiting rearms the next wait")
    }

    static func agentChecks(_ origin: Date) {
        func decoded(_ json: String) -> AgentActivity { AgentActivity.claude(Data(json.utf8))! }
        func time(_ seconds: Double) -> Date { origin.addingTimeInterval(seconds) }
        let busy = decoded(#"[{"kind":"interactive","sessionId":"birch","status":"busy"}]"#)
        let working = decoded(#"[{"kind":"background","id":"lark","state":"working"}]"#)
        let waiting = decoded(#"[{"kind":"interactive","sessionId":"birch","status":"waiting"},{"kind":"background","id":"lark","state":"done"}]"#)
        let both = decoded(#"[{"kind":"interactive","sessionId":"birch","status":"waiting"},{"kind":"background","id":"lark","state":"blocked"}]"#)
        let stopped = decoded("[]")
        check(busy.working && working.working && !both.working && both.waiting == ["birch", "lark"], "agents: only busy interactive or working background agents count")
        check(!decoded(#"[{"kind":"interactive","state":"working"},{"kind":"background","status":"busy","state":"done"}]"#).working && AgentActivity.claude(Data("invalid".utf8)) == nil, "agents: wrong fields, finished agents and malformed JSON do not start a hold")
        check(AgentActivity.codex(live: true, modified: origin, now: time(120)) && !AgentActivity.codex(live: true, modified: origin, now: time(121)) && !AgentActivity.codex(live: false, modified: origin, now: origin), "agents: Codex needs both a live process and a fresh rollout")
        var follow = AgentFollow()
        func action(_ sample: AgentActivity, _ seconds: Double, following: Bool = true, wait: Bool = false) -> AgentFollow.Action {
            follow.decide(sample, at: time(seconds), following: following, sleepWhileWaiting: wait)
        }
        check(action(waiting, 0, following: false) == .hold && action(busy, 1, following: false) == .start, "agents: waiting alone never starts a session")
        check(action(stopped, 30) == .hold && action(stopped, 629) == .hold && action(working, 630) == .hold, "agents: resumed work cancels the stop grace")
        check(action(waiting, 660) == .hold && action(waiting, 1260) == .end, "agents: normal grace ends after ten minutes without work")
        follow = AgentFollow()
        check(action(waiting, 0, wait: true) == .hold && action(both, 1200, wait: true) == .hold && action(both, 3000, wait: true) == .hold && action(both, 3030, wait: true) == .end, "agents: every current waiter must exceed thirty minutes")
        follow.stop()
        check(action(AgentActivity(unavailable: true), 43000, following: false) == .hold && action(working, 43100, following: false) == .hold, "agents: a failed poll cannot undo End")
        check(AgentFollow.cap == 43200 && action(busy, 43200, following: false) == .hold && action(stopped, 43230, following: false) == .hold && action(working, 43260, following: false) == .start, "agents: End or the twelve-hour cap suppresses restart until work stops")
    }
}
