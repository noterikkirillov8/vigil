import Foundation

/// `Vigil -demo`: filming mode. Fictional data, a separate defaults suite, and a controller whose power side is a no-op,
/// so nothing system-wide (lid mode, helper, sudo, pmset, login item, quitting apps, pings) can happen.
enum Demo {
    static let on = CommandLine.arguments.contains("-demo")
    static let apps = ["Notes", "Figma", "Mail", "Calendar", "Music"]
    private static let suite = "com.erikkirillov.Vigil.demo"

    /// Wiped and seeded on every launch; `-demo-agents` also turns on "Start with my agents".
    static func store() -> UserDefaults {
        let d = UserDefaults(suiteName: suite) ?? .standard
        d.removePersistentDomain(forName: suite)
        d.set(true, forKey: "vigilIntroSeen")
        d.set(["Terminal", "Figma", "Notes", "Mail"], forKey: Prefs.keep)
        d.set(true, forKey: Prefs.phonePings)
        d.set("vigil-demo", forKey: Prefs.phoneTopic)
        d.set(CommandLine.arguments.contains("-demo-agents"), forKey: Prefs.followAgents)
        return d
    }

    /// Three fictional agents; the third finishes 8 s after `began`.
    static func agents(since began: Date) -> AgentActivity {
        var a = AgentActivity()
        a.working = true
        a.workingProjects = ["storefront", "orbit"]
        if Date().timeIntervalSince(began) < 8 { a.workingProjects.insert("api-server") }
        return a
    }
}

struct DemoPower: PowerControl {
    func sleepDisplay() {}
    func setLid(_ on: Bool) -> Bool { true }
    func spawnWatchdog(script: String) -> Int32? { nil }
    func killWatchdog(_ pid: Int32) {}
}

struct DemoHelper: SafetyHelperInstaller {
    var isInstalled: Bool { true }
    func install(stateFile: URL) {}
}
