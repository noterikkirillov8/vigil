import Foundation

struct AgentActivity {
    var working = false
    var waiting: Set<String> = []
    var other = false
    var unavailable = false
    var phoneWaiters: Set<String> = []
    var waiterProjects: [String: String] = [:]
    var workingProjects: Set<String> = []

    static func claude(_ data: Data) -> Self? {
        struct Row: Decodable {
            let kind: String
            let id, sessionId, status, state: String?
            let cwd: String?
            let pid: Int?
        }
        guard let rows = try? JSONDecoder().decode([Row].self, from: data) else { return nil }
        var activity = Self()
        for row in rows {
            switch (row.kind, row.kind == "interactive" ? row.status : row.state) {
            case ("interactive", "busy"), ("background", "working"):
                activity.working = true
                if let cwd = row.cwd { activity.workingProjects.insert((cwd as NSString).lastPathComponent) }
            case ("interactive", "waiting"), ("background", "blocked"):
                if let id = row.sessionId ?? row.id ?? row.pid.map(String.init) {
                    activity.waiting.insert(id)
                    if row.status == "waiting", row.kind == "interactive" {
                        activity.phoneWaiters.insert(id)
                        activity.waiterProjects[id] = row.cwd.map { ($0 as NSString).lastPathComponent }
                    }
                }
                else { activity.other = true }
            case ("background", "done"), ("background", "failed"), ("background", "stopped"): break
            default: activity.other = true
            }
        }
        return activity
    }

    static func codex(live: Bool, modified: Date, now: Date) -> Bool {
        live && (0...120).contains(now.timeIntervalSince(modified))
    }
}

struct AgentFollow {
    enum Action { case start, hold, end }
    static let cap: TimeInterval = 12 * 3600
    private var quietSince: Date?
    private var waitingSince: [String: Date] = [:]
    private var suppressed = false

    mutating func stop() { suppressed = true; quietSince = nil }

    mutating func decide(_ activity: AgentActivity, at now: Date, following: Bool, sleepWhileWaiting: Bool) -> Action {
        waitingSince = Dictionary(uniqueKeysWithValues: activity.waiting.map { ($0, waitingSince[$0] ?? now) })
        if activity.working {
            quietSince = nil
            return following || suppressed ? .hold : .start
        }
        if !activity.unavailable { suppressed = false }
        guard following else { quietSince = nil; return .hold }
        if sleepWhileWaiting, !activity.other, let newestWait = waitingSince.values.max() {
            quietSince = nil
            return now.timeIntervalSince(newestWait) > 30 * 60 ? .end : .hold
        }
        if quietSince == nil { quietSince = now }
        return now.timeIntervalSince(quietSince ?? now) >= 10 * 60 ? .end : .hold
    }
}
