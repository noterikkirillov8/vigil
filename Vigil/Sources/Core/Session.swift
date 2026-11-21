import Foundation

/// Manual durations are capped at 24 h. Scheduled sessions have a local-clock deadline.
struct Session: Equatable {
    static let cap: TimeInterval = 24 * 3600
    let start: Date
    private(set) var end: Date

    init(start: Date, length: TimeInterval) { self.start = start; end = start.addingTimeInterval(min(max(length, 0), Self.cap)) }
    init(start: Date, scheduledEnd: Date) { self.start = start; end = scheduledEnd }

    var total: TimeInterval { end.timeIntervalSince(start) }
    func remaining(now: Date) -> TimeInterval { max(0, end.timeIntervalSince(now)) }
    func isOver(now: Date) -> Bool { now >= end }

    mutating func add(_ seconds: TimeInterval, now: Date) {
        end = min(end.addingTimeInterval(seconds), max(end, now.addingTimeInterval(Self.cap)))
    }

    /// Whole seconds shown, rounded up so a 2 h session starts at 2:00:00.
    static func countdown(_ remaining: TimeInterval) -> String {
        let s = Int(remaining.rounded(.up)), h = s / 3600, m = s % 3600 / 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s % 60) : String(format: "%d:%02d", m, s % 60)
    }
    /// Menu bar text: "1:42" over an hour, "42m" under it, minutes round up.
    static func menuText(_ remaining: TimeInterval) -> String {
        let s = Int(remaining)
        return s >= 3600 ? String(format: "%d:%02d", s / 3600, s % 3600 / 60) : "\(Int((remaining / 60).rounded(.up)))m"
    }
    static func endsAt(_ end: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: end)
        return String(format: "Ends at %02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
    /// How many of `segments` LEDs are lit: time left, rounded up.
    static func litSegments(remaining: TimeInterval, total: TimeInterval, segments: Int = 24) -> Int {
        guard total > 0 else { return 0 }
        return min(segments, Int((remaining / total * Double(segments)).rounded(.up)))
    }
}

enum StatusMark {
    case idle, running, lidWarning

    init(session: Session?, lidFailed: Bool) {
        self = session == nil ? .idle : (lidFailed ? .lidWarning : .running)
    }
}

enum Presets {
    static let minutes = [30, 60, 120, 240, 480]
    static let custom = -1
    static func label(_ m: Int) -> String {
        if m == custom { return "Custom" }
        return m < 60 || m % 60 != 0 ? "\(m) min" : "\(m / 60) h"
    }
    /// Custom lengths: 15 min steps, 15 min to 24 h.
    static func snap(_ m: Int) -> Int { min(max((m + 7) / 15 * 15, 15), 1440) }
    static func long(_ m: Int) -> String { m % 60 == 0 ? "\(m / 60) h" : m < 60 ? "\(m) min" : "\(m / 60) h \(m % 60) min" }
}

/// How often the owner should tick: every second while something shows the time, otherwise coarse but never late.
enum Ticker {
    static func interval(visible: Bool, remaining: TimeInterval) -> TimeInterval { visible ? 1 : max(1, min(15, remaining)) }
}
