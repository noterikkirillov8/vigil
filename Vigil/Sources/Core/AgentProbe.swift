import Foundation

enum AgentProbe {
    static func sample(includeCodex: Bool = true) -> AgentActivity {
        let files = FileManager.default, home = files.homeDirectoryForCurrentUser
        let paths = [home.appendingPathComponent(".local/bin").path, "/opt/homebrew/bin", "/usr/local/bin"]
            + (ProcessInfo.processInfo.environment["PATH"] ?? "").components(separatedBy: ":").filter { $0.hasPrefix("/") }
        var activity = AgentActivity()
        if let cli = paths.map({ URL(fileURLWithPath: $0).appendingPathComponent("claude") }).first(where: { files.isExecutableFile(atPath: $0.path) }) {
            activity = output(cli, ["agents", "--json", "--all"]).flatMap(AgentActivity.claude) ?? AgentActivity(unavailable: true)
        }
        guard includeCodex, !activity.working, output(URL(fileURLWithPath: "/usr/bin/pgrep"), ["-u", String(getuid()), "-x", "codex"]) != nil else { return activity }
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
        let sessions = home.appendingPathComponent(".codex/sessions")
        guard let entries = files.enumerator(at: sessions, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else { return activity }
        let now = Date()
        for case let url as URL in entries where url.lastPathComponent.hasPrefix("rollout-") && url.pathExtension == "jsonl" {
            if let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true, let modified = values.contentModificationDate,
               AgentActivity.codex(live: true, modified: modified, now: now) { activity.working = true; break }
        }
        return activity
    }

    private static func output(_ executable: URL, _ arguments: [String]) -> Data? {
        let process = Process(), pipe = Pipe()
        process.executableURL = executable; process.arguments = arguments
        process.standardInput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice; process.standardOutput = pipe
        var environment = ProcessInfo.processInfo.environment
        environment["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] = "1"
        process.environment = environment
        let fd = pipe.fileHandleForReading.fileDescriptor
        guard fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else { return nil }
        do { try process.run() } catch { return nil }
        let deadline = ContinuousClock.now + .seconds(2)
        var data = Data(), buffer = [UInt8](repeating: 0, count: 16384)
        while ContinuousClock.now < deadline {
            let count = read(fd, &buffer, buffer.count)
            if count > 0 {
                data.append(buffer, count: count)
                if data.count > 8 * 1024 * 1024 { break }
            } else if count == 0 && !process.isRunning {
                return process.terminationStatus == 0 ? data : nil
            } else if count < 0 && errno != EAGAIN && errno != EINTR { break }
            else { Thread.sleep(forTimeInterval: 0.01) }
        }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        return nil
    }
}
