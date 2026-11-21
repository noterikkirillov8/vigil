import Foundation
import IOKit
import IOKit.pwr_mgt
import IOKit.ps

/// Real power control. Only the app uses this; tests and QA use fakes.
struct RealPower: PowerControl {
    func setLid(_ on: Bool) -> Bool {
        run(on ? LidCommand.on : LidCommand.off)
    }

    func sleepDisplay() { _ = run(["/usr/bin/pmset", "displaysleepnow"]) }

    private func run(_ argv: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: argv[0])
        p.arguments = Array(argv.dropFirst())
        p.standardInput = FileHandle.nullDevice; p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    /// A shell in its own session, so it outlives the app.
    func spawnWatchdog(script: String) -> Int32? {
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        for fd in 0...2 { posix_spawn_file_actions_addopen(&actions, Int32(fd), "/dev/null", O_RDWR, 0) }
        let args = ["/bin/sh", "-c", script], env = ["PATH=/usr/bin:/bin:/usr/sbin:/sbin"]
        let a = args.map { strdup($0) } + [nil]
        let e = env.map { strdup($0) } + [nil]
        defer { a.forEach { free($0) }; e.forEach { free($0) } }
        var pid: pid_t = 0
        return posix_spawn(&pid, "/bin/sh", &actions, &attr, a, e) == 0 ? pid : nil
    }

    func killWatchdog(_ pid: Int32) { kill(-pid, SIGTERM) }   // its own session, so the group is just the watchdog and its sleep
}

final class IOAssertions: SleepAssertions {
    private var ids: [IOPMAssertionID] = []
    func hold(display: Bool) {
        release()
        var types = [kIOPMAssertionTypePreventUserIdleSystemSleep as String]
        if display { types.append(kIOPMAssertionTypePreventUserIdleDisplaySleep as String) }
        for t in types {
            var id = IOPMAssertionID(0)
            if IOPMAssertionCreateWithName(t as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Vigil session" as CFString, &id) == kIOReturnSuccess { ids.append(id) }
        }
    }
    func release() { ids.forEach { IOPMAssertionRelease($0) }; ids = [] }
}

enum Sys {
    static func battery() -> BatteryState? {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let list = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        guard let src = list.first, let d = IOPSGetPowerSourceDescription(info, src)?.takeUnretainedValue() as? [String: Any],
              let pct = d[kIOPSCurrentCapacityKey] as? Int else { return nil }
        return BatteryState(onBattery: (d[kIOPSPowerSourceStateKey] as? String) == kIOPSBatteryPowerValue, percent: pct)
    }

    /// Seconds since the last keyboard or mouse input (IOHIDSystem, no permission needed).
    static func idleSeconds() -> TimeInterval {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard svc != 0 else { return 0 }
        defer { IOObjectRelease(svc) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let d = props?.takeRetainedValue() as? [String: Any], let ns = d["HIDIdleTime"] as? NSNumber else { return 0 }
        return ns.doubleValue / 1_000_000_000
    }
}

extension Backstop: SafetyHelperInstaller {
    private var url: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(Self.label).plist")
    }
    private var domain: String { "gui/\(getuid())" }
    var isInstalled: Bool { FileManager.default.fileExists(atPath: url.path) }

    func install(stateFile: URL) {
        guard let data = try? PropertyListSerialization.data(fromPropertyList: Self.plist(stateFile: stateFile.path), format: .xml, options: 0) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard (try? data.write(to: url, options: .atomic)) != nil else { return }
        _ = launchctl(["bootstrap", domain, url.path])
    }
    func remove() -> Bool {
        let status = launchctl(["bootout", "\(domain)/\(Self.label)"])
        guard status == 0 || status == ESRCH || status == 113 else { return false }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            return true
        } catch {
            if status == 0 { _ = launchctl(["bootstrap", domain, url.path]) }
            return false
        }
    }
    private func launchctl(_ args: [String]) -> Int32? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        p.waitUntilExit(); return p.terminationStatus
    }
}
