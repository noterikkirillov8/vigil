import Foundation

struct BatteryState: Equatable { var onBattery: Bool; var percent: Int }

struct NightSchedule {
    var from: Int
    var to: Int

    func endIfDue(at now: Date, calendar: Calendar, running: Bool, battery: @autoclosure () -> BatteryState?, floor: Int) -> Date? {
        guard !running, from != to, (0..<1440).contains(from), (0..<1440).contains(to) else { return nil }
        let today = calendar.startOfDay(for: now)
        func time(_ minutes: Int, on day: Date) -> Date? {
            calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day,
                          matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
        }
        guard let start = time(from, on: today), now >= start, now.timeIntervalSince(start) < 60,
              let endDay = calendar.date(byAdding: .day, value: to < from ? 1 : 0, to: today),
              let end = time(to, on: endDay), end > now else { return nil }
        if floor > 0, let battery = battery(), Battery.floorHit(onBattery: battery.onBattery, percent: battery.percent, floor: floor) { return nil }
        return end
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
