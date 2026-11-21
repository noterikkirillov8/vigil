import Foundation

enum PhonePing: String, CaseIterable {
    case ended = "Vigil session ended."
    case finished = "Agents finished. Vigil ended the session."
    case hot = "Mac too hot. Vigil ended the session."
    case waiting = "An agent has been waiting for you for over 15 min."

    static func newTopic() -> String {
        let letters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        return "vigil-" + String((0..<16).map { _ in letters.randomElement()! })
    }

    static func link(_ topic: String) -> URL? {
        guard topic.wholeMatch(of: /vigil-[a-zA-Z0-9]{16}/) != nil else { return nil }
        return URL(string: "https://ntfy.sh/" + topic)
    }

    func message(projects: Set<String>, includeNames: Bool = false) -> String {
        guard includeNames else { return rawValue }
        let names = projects.compactMap { path -> String? in
            let leaf = (path as NSString).lastPathComponent.components(separatedBy: .controlCharacters).joined(separator: " ")
            return leaf.isEmpty || leaf == "/" ? nil : String(leaf.prefix(60))
        }
        let suffix = Set(names).sorted().prefix(3).joined(separator: ", ")
        return suffix.isEmpty ? rawValue : rawValue + " " + suffix
    }

    func post(enabled: Bool, topic: String, projects: Set<String> = [], includeNames: Bool = false, send: (URLRequest) -> Void) {
        guard enabled, let url = Self.link(topic) else { return }
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "POST"
        request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(message(projects: projects, includeNames: includeNames).utf8)
        send(request)
    }
}

struct WaitPings {
    private var since: [String: Date] = [:]
    private var sent: Set<String> = []

    mutating func due(_ activity: AgentActivity, at now: Date) -> Set<String> {
        guard !activity.unavailable else { since.removeAll(); return [] }
        let waiting = activity.phoneWaiters
        sent.formIntersection(waiting)
        since = Dictionary(uniqueKeysWithValues: waiting.map { ($0, since[$0] ?? now) })
        let due = waiting.subtracting(sent).filter { now.timeIntervalSince(since[$0] ?? now) > 15 * 60 }
        sent.formUnion(due)
        return due
    }
}
