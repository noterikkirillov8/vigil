import AppKit
import SwiftUI

struct VigilView: View {
    @Bindable var model: VigilModel
    var onHeight: (CGFloat) -> Void = { _ in }
    var holdPreview: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduce
    @AppStorage(Prefs.lid, store: Prefs.store) private var lid = true
    @State private var copied = false

    var body: some View {
        let panel = KitPanel(title: "Vigil", width: 340, trailing: {
            if model.running { KitBadge(text: "Awake") }
        }, content: {
            VStack(spacing: 16) { if model.running { running } else { idle }; notices }.padding(18)
        }, footer: {
            HStack {
                Button("Settings") { model.onSettings() }.buttonStyle(.kitQuiet)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.kitQuiet)
            }.padding(.horizontal, -14).padding(.vertical, -6)
        })
        .kitAccent(Prefs.accent)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { onHeight($0) }
        if reduce { panel.opacity(model.shown ? 1 : 0).animation(KitMotion.soft, value: model.shown) } else { panel.kitPanelEntrance(model.shown) }
    }

    private var idle: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Stay awake for").font(KitFont.header).foregroundStyle(KitColor.text2)
                KitSegmented(selection: $model.selected, options: Presets.minutes.map { ($0, Presets.label($0)) })
                HStack {
                    Text("Or set your own").font(KitFont.body).foregroundStyle(KitColor.text2)
                    Spacer()
                    KitStepper(value: $model.custom, range: 15...1440, step: 15, format: Presets.long)
                        .opacity(model.selected == Presets.custom ? 1 : 0.45)   // a preset is in use
                        .animation(KitMotion.snap, value: model.selected)
                }
                .padding(.top, 4)
            }
            .onChange(of: model.custom) { _, _ in model.selected = Presets.custom }
            KitSection { KitToggleRow(title: "Stay awake with the lid closed", isOn: $lid) }
            WideButton(title: "Start", kind: .primary) { model.start() }.keyboardShortcut(.defaultAction)   // Return starts
        }
    }

    private var running: some View {
        let s = model.session ?? Session(start: model.now, length: 0)
        let left = s.remaining(now: model.now)
        return VStack(alignment: .leading, spacing: 14) {
            if model.followingAgents {
                Text("Following your agents").font(KitFont.title).foregroundStyle(KitColor.text)
            } else {
                Text(Session.countdown(left))
                    .font(KitFont.figure(44))
                    .foregroundStyle(KitColor.text)
                    .kitRollingNumber(Int(left.rounded(.up)))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            NightStrip(lit: Session.litSegments(remaining: left, total: s.total))
            HStack(spacing: 6) {
                Text(model.followingAgents ? "12 hour limit" : Session.endsAt(s.end)).font(KitFont.detail).foregroundStyle(KitColor.text2).monospacedDigit()
                Spacer()
                KitLed(on: model.lidActive)
                Text(model.lidActive ? "Lid mode on" : "Lid mode off").font(KitFont.detail).foregroundStyle(KitColor.text2)
            }
            HStack(spacing: 8) {
                WideButton(title: "+30 min", kind: .secondary) { model.add(minutes: 30) }
                    .disabled(model.followingAgents).opacity(model.followingAgents ? 0.45 : 1)
                HoldEnd(progress: holdPreview) { model.end() }
            }
        }
    }

    @ViewBuilder private var notices: some View {
        if model.lidFailed {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    KitLed(color: KitColor.amber)
                    Text("Lid mode needs a one-time setup").font(KitFont.body).foregroundStyle(KitColor.text)
                }
                WideButton(title: copied ? "Copied" : "Copy setup command", kind: .secondary) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(LidCommand.setup, forType: .string)
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(2)); copied = false }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).transition(.kitRow)
        }
        if model.insomnia {
            HStack(spacing: 8) {
                KitLed(color: KitColor.amber)
                Text("Insomnia is running too. Use one at a time.").font(KitFont.detail).foregroundStyle(KitColor.text2)
                Spacer(minLength: 0)
            }.transition(.kitRow)
        }
    }
}

/// The signature: 24 LED segments, lit = time left, going dark one by one from the right.
struct NightStrip: View {
    let lit: Int
    @Environment(\.kitAccent) private var accent
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<24, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5).fill(i < lit ? accent : KitColor.well).frame(height: 14)
            }
        }
        .animation(KitMotion.soft, value: lit)
        .accessibilityElement().accessibilityLabel("Time left").accessibilityValue("\(lit) of 24")
    }
}

/// Full-width key in the kit's button look (the kit's own buttons size to their label).
struct WideButton: View {
    enum Kind { case primary, secondary }
    let title: String
    let kind: Kind
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(title).font(KitFont.button).lineLimit(1)
                .foregroundStyle(kind == .primary ? KitColor.window : KitColor.text)
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(RoundedRectangle(cornerRadius: KitSpace.controlRadius)
                    .fill(kind == .primary ? KitColor.text.opacity(hover ? 0.88 : 1) : (hover ? KitColor.well : .clear)))
                .overlay(RoundedRectangle(cornerRadius: KitSpace.controlRadius).strokeBorder(kind == .primary ? .clear : KitColor.line, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: KitSpace.controlRadius))
        }
        .buttonStyle(PressStyle())
        .onHover { h in withAnimation(KitMotion.soft) { hover = h } }
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.97 : 1).animation(KitMotion.press, value: configuration.isPressed)
    }
}

/// End: press and hold 0.6 s, a red fill runs along the key; letting go early cancels.
struct HoldEnd: View {
    @State var progress: CGFloat = 0
    let action: () -> Void

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: KitSpace.controlRadius).fill(KitColor.red.opacity(0.08))
            GeometryReader { g in Rectangle().fill(KitColor.red.opacity(0.3)).frame(width: g.size.width * progress) }
                .clipShape(RoundedRectangle(cornerRadius: KitSpace.controlRadius))
            Text("End").font(KitFont.button).foregroundStyle(KitColor.red).frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32)
        .overlay(RoundedRectangle(cornerRadius: KitSpace.controlRadius).strokeBorder(KitColor.red.opacity(0.5), lineWidth: 1))
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.6, maximumDistance: 40, perform: { action() }, onPressingChanged: { down in
            if down { withAnimation(.linear(duration: 0.6)) { progress = 1 } } else { withAnimation(KitMotion.soft) { progress = 0 } }
        })
        .help("Hold to end")
        .accessibilityLabel("End session").accessibilityAddTraits(.isButton).accessibilityAction { action() }
    }
}
