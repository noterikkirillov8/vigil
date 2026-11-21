import AppKit
import SwiftUI

/// `Vigil -qa <dir>`: renders the real views with fake data to PNGs, then quits. Off-screen only, no controller,
/// no status item, nothing that can touch power settings.
@MainActor
enum QA {
    static func renderHotspotIfAsked() -> Bool {
        let args = CommandLine.arguments
        guard args.contains("-hotspot-only"), let index = args.firstIndex(of: "-qa"), index + 1 < args.count else { return false }
        NSApp?.setActivationPolicy(.prohibited)
        let renderer = ImageRenderer(content: HotspotSettings().kitAccent(Prefs.accent)
            .padding(20).frame(width: 520).background(KitColor.window).environment(\.colorScheme, .dark))
        renderer.scale = 2
        guard let image = renderer.cgImage, let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { exit(1) }
        let url = URL(fileURLWithPath: args[index + 1]).appendingPathComponent("25-hotspot-settings.png")
        do { try png.write(to: url) } catch { exit(1) }
        return true
    }

    static func renderPhoneIfAsked() -> Bool {
        let args = CommandLine.arguments
        guard args.contains("-phone-only"), let index = args.firstIndex(of: "-qa"), index + 1 < args.count else { return false }
        NSApp?.setActivationPolicy(.prohibited)
        let renderer = ImageRenderer(content: PhoneSettings(enabled: .constant(true), topic: "vigil-4pL8bR2wT6cN9sK3", includeNames: .constant(false))
            .kitAccent(Prefs.accent).padding(20).frame(width: 520).background(KitColor.window).environment(\.colorScheme, .dark))
        renderer.scale = 2
        guard let image = renderer.cgImage, let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { exit(1) }
        let url = URL(fileURLWithPath: args[index + 1]).appendingPathComponent("24-phone-pings.png")
        do { try png.write(to: url) } catch { exit(1) }
        return true
    }

    static func renderNightIfAsked() -> Bool {
        let args = CommandLine.arguments
        guard args.contains("-night-only"), let index = args.firstIndex(of: "-qa"), index + 1 < args.count else { return false }
        NSApp?.setActivationPolicy(.prohibited)
        let renderer = ImageRenderer(content: NightSettings(enabled: .constant(true), from: .constant(60), to: .constant(420)).kitAccent(Prefs.accent)
            .padding(20).frame(width: 520).background(KitColor.window).environment(\.colorScheme, .dark))
        renderer.scale = 2
        guard let image = renderer.cgImage, let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { exit(1) }
        let url = URL(fileURLWithPath: args[index + 1]).appendingPathComponent("23-night-schedule.png")
        do { try png.write(to: url) } catch { exit(1) }
        return true
    }

    static func renderLidIfAsked() -> Bool {
        let args = CommandLine.arguments
        guard args.contains("-lid-only"), let index = args.firstIndex(of: "-qa"), index + 1 < args.count else { return false }
        NSApp?.setActivationPolicy(.prohibited)
        let renderer = ImageRenderer(content: LidSettings(lidSaver: .constant(true), heatGuard: .constant(true)).kitAccent(Prefs.accent)
            .padding(20).frame(width: 520).background(KitColor.window).environment(\.colorScheme, .dark))
        renderer.scale = 2
        guard let image = renderer.cgImage, let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { exit(1) }
        let url = URL(fileURLWithPath: args[index + 1]).appendingPathComponent("22-lid-closed-settings.png")
        do { try png.write(to: url) } catch { exit(1) }
        return true
    }

    static func renderAgentsIfAsked() -> Bool {
        let args = CommandLine.arguments
        guard args.contains("-agents-only"), let index = args.firstIndex(of: "-qa"), index + 1 < args.count else { return false }
        let dir = URL(fileURLWithPath: args[index + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let model = VigilModel(live: false)
        model.shown = true; model.followingAgents = true
        model.demo(remaining: 11 * 3600, total: AgentFollow.cap)
        func render(_ view: some View, _ name: String) {
            let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
            renderer.scale = 2
            guard let image = renderer.cgImage, let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { exit(1) }
            do { try png.write(to: dir.appendingPathComponent(name)) } catch { exit(1) }
        }
        render(VigilView(model: model).padding(24).background(Color(hex: 0x3A3B3E)), "18-following-agents.png")
        render(AutomaticSettings(followAgents: .constant(true), sleepWhileWaiting: .constant(false)).kitAccent(Prefs.accent)
            .padding(20).frame(width: 520).background(KitColor.window), "19-automatic-switches.png")
        return true
    }

    /// `-demo -demo-only -qa <dir>`: the panel and the settings tabs that show personal data, in demo state.
    static func renderDemoIfAsked() -> Bool {
        let args = CommandLine.arguments
        guard Demo.on, args.contains("-demo-only"), let index = args.firstIndex(of: "-qa"), index + 1 < args.count else { return false }
        let dir = URL(fileURLWithPath: args[index + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSApp?.setActivationPolicy(.prohibited)
        Prefs.register()
        func panel(_ name: String, tweak: (VigilModel) -> Void = { _ in }) {
            let model = VigilModel(live: false)
            model.shown = true
            tweak(model)
            capture(NSHostingView(rootView: VigilView(model: model).padding(24).background(Color(hex: 0x3A3B3E)).environment(\.colorScheme, .dark)), dark: true, name: name, dir: dir)
        }
        panel("40-demo-idle")
        panel("41-demo-running") { $0.demo(remaining: 2 * 3600 - 4, total: 2 * 3600) }
        panel("42-demo-agents") { $0.demo(remaining: 11 * 3600, total: AgentFollow.cap); $0.followingAgents = true }
        for (n, tab) in [SettingsTab.automatic, .away].enumerated() {
            Prefs.store.set(tab.rawValue, forKey: Prefs.tab)
            Prefs.store.set(true, forKey: Prefs.away)
            capture(NSHostingView(rootView: SettingsView(model: VigilModel(live: false)).environment(\.colorScheme, .dark)), dark: true, name: "4\(3 + n)-demo-settings-\(tab.rawValue.lowercased())", dir: dir)
        }
        let topic = Prefs.store.string(forKey: Prefs.phoneTopic) ?? ""
        capture(NSHostingView(rootView: PhoneSettings(enabled: .constant(true), topic: topic, includeNames: .constant(false)).kitAccent(Prefs.accent)
            .padding(20).frame(width: 520).background(KitColor.window).environment(\.colorScheme, .dark)), dark: true, name: "45-demo-phone", dir: dir)
        print("keep:", Prefs.keepList, "apps:", Demo.apps)
        return true
    }

    static func renderStatusIfAsked() -> Bool {
        let args = CommandLine.arguments
        guard args.contains("-status-only"), let index = args.firstIndex(of: "-qa"), index + 1 < args.count else { return false }
        statusItems(URL(fileURLWithPath: args[index + 1], isDirectory: true))
        return true
    }

    static func runIfAsked() -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-qa"), i + 1 < args.count else { return false }
        let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSApp.setActivationPolicy(.prohibited)
        Prefs.register()
        UserDefaults.standard.set(true, forKey: Prefs.lid)

        func scene(_ name: String, dark: Bool = true, hold: CGFloat = 0, tweak: (VigilModel) -> Void = { _ in }) {
            let model = VigilModel(live: false)
            model.shown = true
            tweak(model)
            let host = NSHostingView(rootView: VigilView(model: model, holdPreview: hold).padding(24)
                .background(dark ? Color(hex: 0x3A3B3E) : Color(hex: 0xC9C8C3)).environment(\.colorScheme, dark ? .dark : .light))
            capture(host, dark: dark, name: name, dir: dir)
        }
        let h: TimeInterval = 3600
        scene("18-following-agents") { $0.demo(remaining: 11 * h, total: AgentFollow.cap); $0.followingAgents = true }
        scene("01-idle")
        scene("02-idle-custom") { $0.selected = Presets.custom; $0.custom = 135 }
        scene("03-running-start") { $0.demo(remaining: 2 * h, total: 2 * h) }
        scene("04-running-mid") { $0.demo(remaining: 6127, total: 2 * h) }
        scene("05-running-low") { $0.demo(remaining: 752, total: 2 * h) }
        scene("06-running-last-seconds") { $0.demo(remaining: 9, total: 30 * 60) }
        scene("07-running-24h") { $0.demo(remaining: 23 * h + 1500, total: 24 * h) }
        scene("08-running-hold-end", hold: 0.55) { $0.demo(remaining: 6127, total: 2 * h) }
        scene("09-running-lid-off") { $0.demo(remaining: 3 * h, total: 4 * h, lid: false) }
        scene("10-setup-row-idle") { $0.lidFailed = true }
        scene("11-setup-row-running") { $0.demo(remaining: 6127, total: 2 * h, lid: false); $0.lidFailed = true }
        scene("12-insomnia-idle") { $0.insomnia = true }
        scene("13-insomnia-running") { $0.demo(remaining: 6127, total: 2 * h); $0.insomnia = true }
        scene("14-both-rows-running") { $0.demo(remaining: 6127, total: 2 * h, lid: false); $0.lidFailed = true; $0.insomnia = true }
        scene("15-light-idle", dark: false)
        scene("16-light-running", dark: false) { $0.demo(remaining: 6127, total: 2 * h) }
        scene("17-light-setup-insomnia", dark: false) { $0.demo(remaining: 6127, total: 2 * h, lid: false); $0.lidFailed = true; $0.insomnia = true }

        for dark in [true, false] {
            for (n, t) in SettingsTab.allCases.enumerated() {
                UserDefaults.standard.set(t.rawValue, forKey: Prefs.tab)
                let model = VigilModel(live: false)
                model.safetyHelperInstalled = t == .about
                let host = NSHostingView(rootView: SettingsView(model: model).environment(\.colorScheme, dark ? .dark : .light))
                capture(host, dark: dark, name: "2\(dark ? 0 : 1)-settings-\(n + 1)-\(t.rawValue.lowercased())\(dark ? "" : "-light")", dir: dir)
            }
        }
        UserDefaults.standard.set("General", forKey: Prefs.tab)
        statusItems(dir)
        NSApp.terminate(nil)
        return true
    }

    /// Off-screen: the hosting view is laid out and drawn without any window.
    static func capture(_ host: NSView, dark: Bool, name: String, dir: URL) {
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(name).png"))
    }

    /// Idle, running and lid-warning marks on a dark and a light bar, at 4x.
    private static func statusItems(_ dir: URL) {
        let scale: CGFloat = 4
        let tile = NSSize(width: 384 * scale, height: 56 * scale)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(tile.width), pixelsHigh: Int(tile.height), bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        for (half, dark) in [(0, true), (1, false)] {
            let bar = NSRect(x: CGFloat(half) * tile.width / 2, y: 0, width: tile.width / 2, height: tile.height)
            (dark ? NSColor(srgbRed: 0.1, green: 0.1, blue: 0.11, alpha: 1) : NSColor(srgbRed: 0.85, green: 0.85, blue: 0.83, alpha: 1)).setFill()
            bar.fill()
            let ink: NSColor = dark ? .white : .black
            var x = bar.minX + 20 * scale
            for (mark, text) in [(StatusMark.idle, ""), (.running, "1:42"), (.lidWarning, "42m")] {
                let img = StatusImage.make(mark)
                let tinted = NSImage(size: img.size, flipped: false) { r in
                    img.draw(in: r); ink.setFill(); r.fill(using: .sourceIn); return true
                }
                let r = NSRect(x: x, y: (tile.height - img.size.height * scale) / 2, width: img.size.width * scale, height: img.size.height * scale)
                tinted.draw(in: r)
                x += r.width
                if !text.isEmpty {
                    let attr = NSMutableAttributedString(attributedString: StatusImage.title(text))
                    attr.addAttributes([.font: NSFont.monospacedDigitSystemFont(ofSize: 12 * scale, weight: .medium), .foregroundColor: ink], range: NSRange(location: 0, length: attr.length))
                    attr.draw(at: NSPoint(x: x, y: (tile.height - attr.size().height) / 2))
                    x += attr.size().width
                }
                x += 18 * scale
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("30-menu-bar-image.png"))
    }
}
