import Foundation

struct BatteryState: Equatable { var onBattery: Bool; var percent: Int }

struct NightSchedule {
    var from: Int
    var to: Int

    /// The night window that contains `now` and has not been handled yet (`lastRun` is the start of the last handled window).
    /// Catches up: a Mac that wakes or an app that starts inside the window still gets tonight's session, ending at the window end.
    func pending(at now: Date, calendar: Calendar, lastRun: Date?) -> (start: Date, end: Date)? {
        guard from != to, (0..<1440).contains(from), (0..<1440).contains(to) else { return nil }
        func time(_ minutes: Int, on day: Date) -> Date? {
            calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day,
                          matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
        }
        let today = calendar.startOfDay(for: now)
        var startDay = today
        guard var start = time(from, on: today) else { return nil }
        if start > now {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today), let s = time(from, on: yesterday) else { return nil }
            startDay = yesterday; start = s
        }
        guard let endDay = calendar.date(byAdding: .day, value: to < from ? 1 : 0, to: startDay),
              let end = time(to, on: endDay), end > now, lastRun.map({ $0 < start }) ?? true else { return nil }
        return (start, end)
    }

    /// Whether a pending night should be skipped: something is already running, or the battery is at or below the floor.
    func skips(running: Bool, battery: @autoclosure () -> BatteryState?, floor: Int) -> Bool {
        if running { return true }
        if floor > 0, let b = battery(), Battery.floorHit(onBattery: b.onBattery, percent: b.percent, floor: floor) { return true }
        return false
    }

    func endIfDue(at now: Date, calendar: Calendar, running: Bool, battery: @autoclosure () -> BatteryState?, floor: Int, lastRun: Date? = nil) -> Date? {
        guard let w = pending(at: now, calendar: calendar, lastRun: lastRun), !skips(running: running, battery: battery(), floor: floor) else { return nil }
        return w.end
    }
}

enum Battery {
    /// Floor 0 means off.
    static func floorHit(onBattery: Bool, percent: Int, floor: Int) -> Bool { floor > 0 && onBattery && percent <= floor }
}

struct AppInfo: Equatable { var name: String; var pid: Int32 }

enum Away {
    static let defaultKeep = [
        "Claude", "Codex", "Terminal", "iTerm2", "Ghostty", "Warp", "Tailscale", "Ollama", "Finder",
        "Xcode", "Visual Studio Code", "Cursor", "Zed", "Sublime Text", "Nova",
        "Safari", "Google Chrome", "Brave Browser", "Arc", "Firefox",
        "Notes", "Mail", "Messages", "Pages", "Numbers", "Keynote"
    ]

    static func isAway(idle: TimeInterval, minutes: Int) -> Bool { idle >= Double(minutes) * 60 }

    /// Which regular apps to quit: none unless away and not done already this away period; never the keep list or Vigil.
    static func select(running: [AppInfo], keep: [String], idle: TimeInterval, minutes: Int, alreadyQuit: Bool, selfPid: Int32) -> [AppInfo] {
        guard isAway(idle: idle, minutes: minutes), !alreadyQuit else { return [] }
        let kept = Set(keep.map { $0.lowercased() })
        return running.filter { $0.pid != selfPid && $0.name.lowercased() != "vigil" && !kept.contains($0.name.lowercased()) }
    }
}
