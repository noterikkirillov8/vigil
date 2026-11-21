import AppKit
import Carbon
import SwiftUI

enum SettingsTab: String, CaseIterable { case general = "General", away = "Away", battery = "Battery", sounds = "Sounds", about = "About", automatic = "Automatic" }

/// The global start/end hot key, kept in UserDefaults as JSON. No default key.
enum HotKeyPref {
    static let key = "vigilHotKey"

    static func load() -> KitHotKey? {
        Prefs.store.data(forKey: key).flatMap { try? JSONDecoder().decode(KitHotKey.self, from: $0) }
    }
    static func save(_ k: KitHotKey?) {
        if let k, let d = try? JSONEncoder().encode(k) { Prefs.store.set(d, forKey: key) } else { Prefs.store.removeObject(forKey: key) }
    }
    static func carbon(_ k: KitHotKey) -> HotKeys.Combo {
        let f = NSEvent.ModifierFlags(rawValue: k.modifiers)
        var m = 0
        if f.contains(.command) { m |= cmdKey }
        if f.contains(.option) { m |= optionKey }
        if f.contains(.control) { m |= controlKey }
        if f.contains(.shift) { m |= shiftKey }
        return .init(keyCode: UInt32(k.keyCode), modifiers: UInt32(m))
    }
}

struct SettingsView: View {
    let model: VigilModel
    @AppStorage(Prefs.tab, store: Prefs.store) private var tab: SettingsTab = .general
    @AppStorage(Prefs.defaultMinutes, store: Prefs.store) private var defaultMinutes = 120
    @AppStorage(Prefs.lid, store: Prefs.store) private var lid = true
    @AppStorage(Prefs.display, store: Prefs.store) private var display = false
    @AppStorage(Prefs.showTime, store: Prefs.store) private var showTime = true
    @AppStorage(Prefs.away, store: Prefs.store) private var away = false
    @AppStorage(Prefs.awayMinutes, store: Prefs.store) private var awayMinutes = 30
    @AppStorage(Prefs.floor, store: Prefs.store) private var floor = 10
    @AppStorage(Prefs.followAgents, store: Prefs.store) private var followAgents = false
    @AppStorage(Prefs.sleepWhileWaiting, store: Prefs.store) private var sleepWhileWaiting = false
    @AppStorage(Prefs.lidSaver, store: Prefs.store) private var lidSaver = true
    @AppStorage(Prefs.heatGuard, store: Prefs.store) private var heatGuard = true
    @AppStorage(Prefs.nightly, store: Prefs.store) private var nightly = false
    @AppStorage(Prefs.nightFrom, store: Prefs.store) private var nightFrom = 60
    @AppStorage(Prefs.nightTo, store: Prefs.store) private var nightTo = 420
    @AppStorage(Prefs.phonePings, store: Prefs.store) private var phonePings = false
    @AppStorage(Prefs.phoneTopic, store: Prefs.store) private var phoneTopic = ""
    @AppStorage(Prefs.includeNames, store: Prefs.store) private var includeNames = false
    @State private var hotKey: KitHotKey? = HotKeyPref.load()
    @State private var keep = Prefs.keepList
    @State private var pick = ""

    var body: some View {
        KitSettings(title: "Vigil settings", tabs: SettingsTab.allCases.map { ($0, $0.rawValue) }, selection: $tab) { t in
            switch t {
            case .general: general
            case .away: awayTab
            case .battery: battery
            case .automatic:
                AutomaticSettings(followAgents: $followAgents, sleepWhileWaiting: $sleepWhileWaiting)
                NightSettings(enabled: $nightly, from: $nightFrom, to: $nightTo)
                LidSettings(lidSaver: $lidSaver, heatGuard: $heatGuard)
                PhoneSettings(enabled: Binding(get: { phonePings }, set: { on in
                    if on, PhonePing.link(phoneTopic) == nil { phoneTopic = PhonePing.newTopic() }
                    phonePings = on
                }), topic: phoneTopic, includeNames: $includeNames)
                HotspotSettings()
            case .sounds: KitSoundSection()
            case .about:
                KitAboutView(name: "Vigil", tagline: "Keeps your Mac awake for a set time, lid closed, and always ends.")
                    .onAppear { model.refreshSafetyHelper() }
                if model.safetyHelperInstalled {
                    KitSection {
                        KitRow(title: "Lid mode", detail: model.lidActive ? "End the lid session to remove the helper." : model.helperRemovalFailed ? "Couldn’t remove the helper. Try again." : "Reinstalls on the next lid session.") {
                            Button("Remove safety helper") { model.removeSafetyHelper() }.buttonStyle(.kitSecondary).disabled(model.lidActive)
                        }
                    }
                }
            }
        }
        .kitAccent(Prefs.accent)
        .onChange(of: hotKey) { _, k in HotKeyPref.save(k); model.onHotKey(k) }
        .onChange(of: defaultMinutes) { _, _ in model.applyDefaultLength() }
        .onChange(of: showTime) { _, _ in model.onStatus() }
        .onChange(of: followAgents) { _, _ in model.configureAgentPolling() }
        .onChange(of: phonePings) { _, _ in model.configureAgentPolling() }
        .onChange(of: lidSaver) { _, _ in model.refreshLidGuard() }
        .onChange(of: heatGuard) { _, _ in model.refreshLidGuard() }
        .onChange(of: nightly) { _, _ in model.configureNightSchedule() }
    }

    private var general: some View {
        KitSection {
            KitRow(title: "Default length") {
                KitSegmented(selection: $defaultMinutes, options: Presets.minutes.map { ($0, Presets.label($0)) }).frame(width: 326)
            }
            KitToggleRow(title: "Stay awake with the lid closed", isOn: $lid)
            KitToggleRow(title: "Keep the display on", isOn: $display)
            KitToggleRow(title: "Show time in menu bar", isOn: $showTime)
            KitToggleRow(title: "Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
            KitRow(title: "Start or end a session", detail: "Global shortcut") { KitHotKeyField(hotKey: $hotKey) }
            KitRow(title: "Intro") { Button("Show intro") { model.onShowIntro() }.buttonStyle(.kitSecondary) }
        }
    }

    @ViewBuilder private var awayTab: some View {
        KitSection(footer: "During a session, apps in the Dock quit once, like ⌘Q. They may still ask to save.") {
            KitToggleRow(title: "Quit apps when I'm away", isOn: $away)
            KitRow(title: "Away after") { KitStepper(value: $awayMinutes, range: 5...240, step: 5, format: { "\($0) min" }) }.disabled(!away)
        }
        KitSection(title: "Never quit these") {
            ForEach(keep, id: \.self) { name in
                KitRow(title: name) {
                    KitIconButton(symbol: "xmark", help: "Remove \(name)") { keep.removeAll { $0 == name }; Prefs.keepList = keep }
                }
            }
            KitRow(title: "Add an app") {
                KitSelect(selection: $pick, options: [("", "Choose")] + runningApps.map { ($0, $0) })
            }
        }
        .disabled(!away)
        .onChange(of: pick) { _, name in
            guard !name.isEmpty else { return }
            keep.append(name); Prefs.keepList = keep; pick = ""
        }
    }

    private var runningApps: [String] {
        let names = Demo.on ? Demo.apps : NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.compactMap(\.localizedName)
        return Array(Set(names)).filter { n in !keep.contains(where: { $0.lowercased() == n.lowercased() }) && n != "Vigil" }.sorted()
    }

    private var battery: some View {
        KitSection(footer: "On battery at or below this level, the session ends with a sound.") {
            KitRow(title: "Stop at") {
                HStack(spacing: 12) {
                    KitSlider(value: Binding(get: { Double(floor) }, set: { floor = Int($0.rounded()) }), range: 0...30, step: 1).frame(width: 180)
                    Text(floor == 0 ? "Off" : "\(floor)%").font(KitFont.figure(12)).foregroundStyle(KitColor.text).frame(width: 36, alignment: .trailing)
                }
            }
        }
    }
}

struct AutomaticSettings: View {
    @Binding var followAgents: Bool
    @Binding var sleepWhileWaiting: Bool

    var body: some View {
        KitSection(footer: "Ends 10 min after work stops. Each session lasts at most 12 hours.") {
            KitToggleRow(title: "Stay awake while my agents work", detail: "Follow Claude Code and Codex.", isOn: $followAgents)
            KitToggleRow(title: "Let the Mac sleep while agents wait for me", detail: "After all agents have waited for more than 30 min.", isOn: $sleepWhileWaiting)
                .disabled(!followAgents)
        }
    }
}

struct NightSettings: View {
    @Binding var enabled: Bool
    @Binding var from: Int
    @Binding var to: Int

    var body: some View {
        KitSection(footer: enabled && from == to ? "Choose different start and end times." : nil) {
            KitToggleRow(title: "Stay awake every night", isOn: $enabled)
            KitRow(title: "From") { timeStepper($from, label: "From") }.disabled(!enabled)
            KitRow(title: "To") { timeStepper($to, label: "To") }.disabled(!enabled)
        }
    }

    private func timeStepper(_ value: Binding<Int>, label: String) -> some View {
        KitStepper(value: value, range: 0...1425, step: 15, format: { String(format: "%02d:%02d", $0 / 60, $0 % 60) })
            .accessibilityLabel(label)
    }
}

struct LidSettings: View {
    @Binding var lidSaver: Bool
    @Binding var heatGuard: Bool

    var body: some View {
        KitSection(title: "When the lid is closed") {
            KitToggleRow(title: "Turn the display off and mute", detail: "During a session, mute the current output.", isOn: $lidSaver)
            KitToggleRow(title: "End if the Mac gets hot", detail: "Restore sleep after 2 minutes of sustained heat.", isOn: $heatGuard)
        }
    }
}

struct PhoneSettings: View {
    @State private var copied = false
    @Binding var enabled: Bool
    let topic: String
    @Binding var includeNames: Bool

    var body: some View {
        KitSection(title: "Phone pings", footer: enabled ? "Install the free ntfy app and subscribe to this topic" : nil) {
            KitToggleRow(title: "Send pings to my phone", isOn: $enabled)
            if enabled {
                KitRow(title: "Topic", detail: topic) {
                    Button(copied ? "Copied" : "Copy link") {
                        guard let link = PhonePing.link(topic) else { return }
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(link.absoluteString, forType: .string)
                        copied = true
                        Task { try? await Task.sleep(for: .seconds(2)); copied = false }
                    }.buttonStyle(.kitSecondary)
                }
                KitToggleRow(title: "Include project names", isOn: $includeNames)
            }
        }
    }
}

struct HotspotSettings: View {
    var body: some View {
        KitSection {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Join my iPhone hotspot when Wi-Fi drops").font(KitFont.body).foregroundStyle(KitColor.text)
                    Text("macOS can do this: set “Ask to join hotspots” to Automatic.")
                        .font(KitFont.detail).foregroundStyle(KitColor.text2)
                }
                Button("Turn it on in Wi-Fi settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Wi-Fi-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }.buttonStyle(.kitSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 11)
        }
    }
}

/// One Settings window for the app's life; created on first use.
@MainActor
final class SettingsController {
    private var window: NSWindow?
    let model: VigilModel
    init(model: VigilModel) { self.model = model }

    func show() {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 560), styleMask: [.titled, .closable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        w.backgroundColor = NSColor(KitColor.window)
        w.contentView = NSHostingView(rootView: SettingsView(model: model))
        w.center()
        window = w
        NSApp.activate()
        w.makeKeyAndOrderFront(nil)
    }
}
