// Kit.swift — shared UI kit for these Mac apps (Tally, Harbor, Sweep, Ledge, Reel).
// Style "Hardware": a small piece of studio gear. Lit LED dots show state, switches have a grip,
// tabs are keys with a lit bar, sliders are tick scales with a needle, titles and figures use wide type.
// Accent is used only for things that are "lit" (LEDs, bars, meters, the selected key). Primary
// buttons are off-white, not accent.
//
// Copy this file unchanged into an app's UI folder. Set the accent once at the root:
//   ContentView().kitAccent(Color(hex: 0x5BD08A))
import AppKit
import SwiftUI

// MARK: - Colours (dark first, also correct in light)

private func dyn(_ light: UInt32, _ dark: UInt32, _ lightAlpha: CGFloat = 1, _ darkAlpha: CGFloat = 1) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        let dark0 = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let hex = dark0 ? dark : light
        return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                       green: CGFloat((hex >> 8) & 0xFF) / 255,
                       blue: CGFloat(hex & 0xFF) / 255,
                       alpha: dark0 ? darkAlpha : lightAlpha)
    })
}

enum KitColor {
    /// Panel / window background. Solid: no materials, no blur.
    static let window = dyn(0xEEEDE9, 0x17181A)
    /// Recessed areas: switch tracks, keys, fields, hovered rows, grouped settings.
    static let well = dyn(0xE4E3DE, 0x1F2023)
    /// Raised: the selected key, pressed states.
    static let raised = dyn(0xFAFAF8, 0x2B2C30)
    /// Hairlines and outlines.
    static let line = dyn(0xD9D8D2, 0x28292D)
    static let text = dyn(0x1B1B1A, 0xECEBE7)
    static let text2 = dyn(0x6C6B67, 0x8F8E8A)
    static let text3 = dyn(0x9E9D98, 0x5C5B58)
    /// Unlit LED / off thumb.
    static let unlit = dyn(0xC4C3BD, 0x3A3B3F)
    static let red = dyn(0xD9453A, 0xF0645A)
    static let amber = dyn(0xC98A12, 0xF2B23E)

    // Older names kept so code written against the first kit still compiles.
    static var surface: Color { well }
    static var fill: Color { well }
    static var fillStrong: Color { raised }
    static var separator: Color { line }
    static var track: Color { unlit }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

// MARK: - Type and spacing

/// Type width switch. Wide (expanded SF) is the family default; an app that prefers standard width sets
/// `KitType.wide = false` once at launch.
/// Typography (Erik, 20 Nov): standard San Francisco for all text; the wide (expanded) cut only on big
/// figures (ports, percentages, sizes), where it reads like a device display. An app that wants no wide
/// type at all sets `KitType.wide = false` once at launch.
@MainActor enum KitType {
    static var wide = true
    static func width(_ f: Font) -> Font { wide ? f.width(.expanded) : f }
}

@MainActor enum KitFont {
    /// Panel and window titles.
    static var title: Font { .system(size: 15, weight: .semibold) }
    /// Big figures: ports, percentages, sizes. `KitFont.figure(19)`. The only place the wide cut appears.
    static func figure(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        KitType.width(.system(size: size, weight: weight)).monospacedDigit()
    }
    static var body: Font { .system(size: 13) }
    static var bodyMedium: Font { .system(size: 13, weight: .medium) }
    static var detail: Font { .system(size: 11) }
    /// Section headers.
    static var header: Font { .system(size: 12, weight: .semibold) }
    /// Key labels (segmented keys, keycaps, badges).
    static var key: Font { .system(size: 12, weight: .medium) }
    static var button: Font { .system(size: 13, weight: .semibold) }
    static var number: Font { .system(size: 13, weight: .medium).monospacedDigit() }
}

enum KitSpace {
    static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 16, xl: CGFloat = 24
    static let panelRadius: CGFloat = 12 // panels and windows
    static let radius: CGFloat = 8       // grouped wells
    static let controlRadius: CGFloat = 5 // keys, buttons, fields
}

/// One motion system for every app. Springs everywhere (they retarget smoothly when interrupted),
/// only transform/opacity animate, nothing moves on its own except a declared "moment".
enum KitMotion {
    /// Controls: switch thumbs, checkboxes, segmented bar, selection.
    static let snap = Animation.spring(duration: 0.24, bounce: 0.14)
    /// Hover highlights, LED fades, colour changes.
    static let soft = Animation.easeOut(duration: 0.14)
    /// Panels and sheets appearing.
    static let panelIn = Animation.spring(duration: 0.32, bounce: 0.16)
    /// Panels and sheets leaving (quicker than arriving).
    static let panelOut = Animation.easeIn(duration: 0.14)
    /// Rows inserting, removing, reordering; numbers changing.
    static let list = Animation.spring(duration: 0.34, bounce: 0.1)
    /// Button press down / release.
    static let press = Animation.spring(duration: 0.18, bounce: 0.25)
    /// Staggered reveals: delay for item `i` (meters lighting, rows on first show).
    static func stagger(_ i: Int, step: Double = 0.018, max: Double = 0.3) -> Animation {
        list.delay(Swift.min(Double(i) * step, max))
    }
}

extension AnyTransition {
    /// Row insert/remove: rises 8 pt and fades in; collapses and fades out.
    static var kitRow: AnyTransition {
        .asymmetric(insertion: .opacity.combined(with: .offset(y: 8)),
                    removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
    }
    /// Inline bars (confirm bars, toasts) sliding up from the bottom edge.
    static var kitBar: AnyTransition { .move(edge: .bottom).combined(with: .opacity) }
}

/// Panel entrance: scale 0.96 -> 1 from the anchor (top for menu bar panels) with a fade.
/// Drive it from the panel controller: set `shown = true` right after `orderFront`, and on close
/// set it false, wait 0.14 s, then `orderOut`.
struct KitPanelEntrance: ViewModifier {
    var shown: Bool
    var anchor: UnitPoint = .top
    func body(content: Content) -> some View {
        content
            .scaleEffect(shown ? 1 : 0.96, anchor: anchor)
            .opacity(shown ? 1 : 0)
            .animation(shown ? KitMotion.panelIn : KitMotion.panelOut, value: shown)
    }
}

extension View {
    func kitPanelEntrance(_ shown: Bool, anchor: UnitPoint = .top) -> some View {
        modifier(KitPanelEntrance(shown: shown, anchor: anchor))
    }
    /// Figures that roll to new values instead of jumping.
    func kitRollingNumber<V: Equatable>(_ value: V) -> some View {
        contentTransition(.numericText()).animation(KitMotion.list, value: value)
    }
}

// MARK: - Accent

extension EnvironmentValues {
    @Entry var kitAccent: Color = Color(hex: 0x5BD08A)
    /// Text/icon colour on top of the accent (use .black for light accents like amber).
    @Entry var kitOnAccent: Color = .black
}

extension View {
    func kitAccent(_ accent: Color, onAccent: Color = .black) -> some View {
        environment(\.kitAccent, accent).environment(\.kitOnAccent, onAccent).tint(accent)
    }
}

// MARK: - LED

/// The signature: a small lit dot. On = accent (or a given colour), off = unlit.
struct KitLed: View {
    var on: Bool = true
    var color: Color? = nil
    var size: CGFloat = 6
    @Environment(\.kitAccent) private var accent

    var body: some View {
        Circle()
            .fill(on ? (color ?? accent) : KitColor.unlit)
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(Color.black.opacity(0.3), lineWidth: 1))
            .accessibilityHidden(true)
    }
}

// MARK: - Switch

private struct KitGrip: View {
    var body: some View {
        HStack(spacing: 2) {
            Rectangle().frame(width: 1, height: 7)
            Rectangle().frame(width: 1, height: 7)
            Rectangle().frame(width: 1, height: 7)
        }
        .foregroundStyle(Color.black.opacity(0.28))
    }
}

/// Grip switch with an LED beside it. `KitSwitch(isOn:)` or `Toggle(...).toggleStyle(.kitSwitch)`.
struct KitSwitch: View {
    @Binding var isOn: Bool
    var showsLed = true
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        HStack(spacing: 8) {
            if showsLed { KitLed(on: isOn) }
            ZStack(alignment: isOn ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 4).fill(KitColor.well)
                RoundedRectangle(cornerRadius: 4).strokeBorder(KitColor.line, lineWidth: 1)
                RoundedRectangle(cornerRadius: 3)
                    .fill(isOn ? KitColor.text : KitColor.text3)
                    .frame(width: 18, height: 14)
                    .overlay(KitGrip())
                    .padding(2)
            }
            .frame(width: 40, height: 18)
        }
        .opacity(enabled ? 1 : 0.4)
        .contentShape(Rectangle())
        .onTapGesture {
            guard enabled else { return }
            withAnimation(KitMotion.snap) { isOn.toggle() }
            KitSound.play(.switchFlip)   // a real light-switch recording (CC0, see Sounds/SOURCES.md)
        }
        .accessibilityRepresentation { Toggle("", isOn: $isOn) }
    }
}

struct KitSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: KitSpace.m) {
            configuration.label.font(KitFont.body).foregroundStyle(KitColor.text)
            Spacer(minLength: KitSpace.s)
            KitSwitch(isOn: configuration.$isOn)
        }
    }
}

extension ToggleStyle where Self == KitSwitchStyle {
    static var kitSwitch: KitSwitchStyle { KitSwitchStyle() }
}

// MARK: - Checkbox (a key with a lit square)

struct KitCheckbox: View {
    @Binding var isOn: Bool
    @Environment(\.kitAccent) private var accent
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3.5).fill(KitColor.well)
            RoundedRectangle(cornerRadius: 3.5).strokeBorder(isOn ? accent.opacity(0.7) : KitColor.line, lineWidth: 1)
            if isOn {
                RoundedRectangle(cornerRadius: 1.5).fill(accent).frame(width: 8, height: 8)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .frame(width: 16, height: 16)
        .opacity(enabled ? 1 : 0.4)
        .contentShape(Rectangle())
        .onTapGesture { if enabled { withAnimation(KitMotion.snap) { isOn.toggle() } } }
        .accessibilityRepresentation { Toggle("", isOn: $isOn) }
    }
}

struct KitCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: KitSpace.s) {
            KitCheckbox(isOn: configuration.$isOn)
            configuration.label.font(KitFont.body).foregroundStyle(KitColor.text)
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(KitMotion.snap) { configuration.isOn.toggle() } }
    }
}

extension ToggleStyle where Self == KitCheckboxStyle {
    static var kitCheckbox: KitCheckboxStyle { KitCheckboxStyle() }
}

// MARK: - Segmented (a row of keys; the selected key is raised with a lit bar)

struct KitSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]
    @Environment(\.kitAccent) private var accent
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 1) {
            ForEach(options, id: \.0) { value, title in
                key(value: value, title: title)
            }
        }
        .background(KitColor.line)
        .clipShape(RoundedRectangle(cornerRadius: KitSpace.controlRadius))
    }

    private func key(value: Value, title: String) -> some View {
        let selected = value == selection
        return Text(title)
            .font(KitFont.key)
            .foregroundStyle(selected ? KitColor.text : KitColor.text2)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 26)
            .background(selected ? KitColor.raised : KitColor.well)
            .overlay(alignment: .bottom) {
                if selected {
                    Rectangle().fill(accent).frame(height: 2).matchedGeometryEffect(id: "bar", in: ns)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(KitMotion.snap) { selection = value } }
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Slider (tick scale with a needle)

struct KitSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var step: Double? = nil
    @Environment(\.kitAccent) private var accent
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let span = range.upperBound - range.lowerBound
            let frac = span > 0 ? CGFloat((value - range.lowerBound) / span).kitClamped(0, 1) : 0
            ZStack(alignment: .leading) {
                KitTicks()
                Rectangle().fill(accent).frame(width: width * frac, height: 2)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(KitColor.text)
                    .frame(width: 4, height: 18)
                    .offset(x: (width - 4) * frac)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                guard enabled, span > 0 else { return }
                let f = Double((drag.location.x / width).kitClamped(0, 1))
                var v = range.lowerBound + f * span
                if let step, step > 0 { v = range.lowerBound + ((v - range.lowerBound) / step).rounded() * step }
                value = min(max(v, range.lowerBound), range.upperBound)
            })
        }
        .frame(height: 20)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityRepresentation { Slider(value: $value, in: range) }
    }
}

private struct KitTicks: View {
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0...10, id: \.self) { i in
                Rectangle().fill(KitColor.line).frame(width: 1, height: i % 5 == 0 ? 10 : 5)
                if i < 10 { Spacer(minLength: 0) }
            }
        }
    }
}

extension CGFloat {
    func kitClamped(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat { Swift.min(Swift.max(self, lo), hi) }
}

// MARK: - Stepper ([−] value [+] as three keys)

struct KitStepper: View {
    @Binding var value: Int
    var range: ClosedRange<Int>
    var step: Int = 1
    var format: (Int) -> String = { "\($0)" }

    var body: some View {
        HStack(spacing: 1) {
            stepKey("minus", enabled: value > range.lowerBound) { value = max(range.lowerBound, value - step) }
            Text(format(value))
                .font(KitFont.figure(12))
                .foregroundStyle(KitColor.text)
                .frame(minWidth: 48, minHeight: 24)
                .background(KitColor.well)
            stepKey("plus", enabled: value < range.upperBound) { value = min(range.upperBound, value + step) }
        }
        .background(KitColor.line)
        .clipShape(RoundedRectangle(cornerRadius: KitSpace.controlRadius))
        .accessibilityElement(children: .ignore)
        .accessibilityValue(format(value))
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: value = min(range.upperBound, value + step)
            case .decrement: value = max(range.lowerBound, value - step)
            @unknown default: break
            }
        }
    }

    private func stepKey(_ symbol: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(enabled ? KitColor.text : KitColor.text3)
                .frame(width: 24, height: 24)
                .background(KitColor.well)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

// MARK: - Select (popup menu with a key-style label)

struct KitSelect<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]

    var body: some View {
        Menu {
            ForEach(options, id: \.0) { value, title in
                Button {
                    selection = value
                } label: {
                    if value == selection { Label(title, systemImage: "checkmark") } else { Text(title) }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(options.first(where: { $0.0 == selection })?.1 ?? "")
                    .font(KitFont.body)
                    .foregroundStyle(KitColor.text)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(KitColor.text2)
            }
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: KitSpace.controlRadius).fill(KitColor.well))
            .overlay(RoundedRectangle(cornerRadius: KitSpace.controlRadius).strokeBorder(KitColor.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

// MARK: - Buttons

struct KitButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, quiet, destructive }
    var kind: Kind = .secondary

    func makeBody(configuration: Configuration) -> some View {
        KitButtonBody(kind: kind, label: configuration.label, pressed: configuration.isPressed)
    }
}

private struct KitButtonBody<Label: View>: View {
    let kind: KitButtonStyle.Kind
    let label: Label
    let pressed: Bool
    @Environment(\.isEnabled) private var enabled
    @State private var hover = false

    var body: some View {
        label
            .font(KitFont.button)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(foreground)
            .padding(.horizontal, 14)
            .frame(minHeight: 28)
            .background(RoundedRectangle(cornerRadius: KitSpace.controlRadius).fill(background))
            .overlay(RoundedRectangle(cornerRadius: KitSpace.controlRadius).strokeBorder(border, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: KitSpace.controlRadius))
            .opacity(enabled ? (pressed ? 0.85 : 1) : 0.4)
            .scaleEffect(pressed ? 0.97 : 1)
            .animation(KitMotion.press, value: pressed)
            .animation(KitMotion.soft, value: hover)
            .onHover { hover = $0 }
    }

    private var foreground: Color {
        switch kind {
        case .primary: KitColor.window
        case .secondary: KitColor.text
        case .quiet: hover ? KitColor.text : KitColor.text2
        case .destructive: KitColor.red
        }
    }

    private var background: Color {
        switch kind {
        case .primary: hover ? KitColor.text.opacity(0.88) : KitColor.text
        case .secondary: hover ? KitColor.well : .clear
        case .quiet: .clear
        case .destructive: KitColor.red.opacity(hover ? 0.18 : 0.08)
        }
    }

    private var border: Color {
        switch kind {
        case .primary, .quiet: .clear
        case .secondary: KitColor.line
        case .destructive: KitColor.red.opacity(0.5)
        }
    }
}

extension ButtonStyle where Self == KitButtonStyle {
    static var kitPrimary: KitButtonStyle { KitButtonStyle(kind: .primary) }
    static var kitSecondary: KitButtonStyle { KitButtonStyle(kind: .secondary) }
    static var kitQuiet: KitButtonStyle { KitButtonStyle(kind: .quiet) }
    static var kitDestructive: KitButtonStyle { KitButtonStyle(kind: .destructive) }
}

/// Square 26 pt key with an SF Symbol. `outlined` draws the key border always (row actions like Stop);
/// `tint` colours it on hover (e.g. KitColor.red for Stop). Always give it a help text.
struct KitIconButton: View {
    let symbol: String
    let help: String
    var outlined = false
    var tint: Color? = nil
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hover ? (tint ?? KitColor.text) : KitColor.text2)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: KitSpace.controlRadius)
                    .fill(hover ? (tint?.opacity(0.16) ?? KitColor.well) : .clear))
                .overlay(RoundedRectangle(cornerRadius: KitSpace.controlRadius)
                    .strokeBorder(hover ? (tint?.opacity(0.6) ?? KitColor.line) : (outlined ? KitColor.line : .clear), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(KitIconPressStyle())
        .onHover { h in withAnimation(KitMotion.soft) { hover = h } }
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct KitIconPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(KitMotion.press, value: configuration.isPressed)
    }
}

// MARK: - Panel (menu bar panels and small windows)

/// Solid panel: title row, hairline, content, optional footer under a hairline.
/// Put it in a borderless NSPanel; never in NSPopover (that adds blur).
struct KitPanel<Trailing: View, Content: View, Footer: View>: View {
    let title: String
    var width: CGFloat = 340
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: KitSpace.s) {
                Text(title).font(KitFont.title).foregroundStyle(KitColor.text)
                Spacer(minLength: KitSpace.s)
                trailing
            }
            .padding(.horizontal, 18)
            .frame(height: 52)
            KitDivider()
            content
            if Footer.self != EmptyView.self {
                KitDivider()
                footer.padding(.horizontal, 18).padding(.vertical, KitSpace.m)
            }
        }
        .frame(width: width)
        .background(KitColor.window)
        .clipShape(RoundedRectangle(cornerRadius: KitSpace.panelRadius))
        .overlay(RoundedRectangle(cornerRadius: KitSpace.panelRadius).strokeBorder(KitColor.line, lineWidth: 1))
    }
}

extension KitPanel where Footer == EmptyView {
    init(title: String, width: CGFloat = 340, @ViewBuilder trailing: () -> Trailing, @ViewBuilder content: () -> Content) {
        self.init(title: title, width: width, trailing: trailing, content: content, footer: { EmptyView() })
    }
}

/// Hairline. `inset` indents it from the leading edge (to line up with row text).
struct KitDivider: View {
    var inset: CGFloat = 0
    var body: some View { Rectangle().fill(KitColor.line).frame(height: 1).padding(.leading, inset) }
}

/// Panel list row: leading slot (a figure, LED or symbol), title, detail, trailing slot.
/// Hover shows a recessed well; pass `actions` to reveal extra buttons only on hover.
struct KitListRow<Leading: View, Trailing: View, Actions: View>: View {
    let title: String
    var detail: String? = nil
    var height: CGFloat = 54
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var actions: Actions
    @State private var hover = false

    var body: some View {
        HStack(spacing: 14) {
            leading
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(KitFont.bodyMedium).foregroundStyle(KitColor.text).lineLimit(1)
                if let detail {
                    Text(detail).font(KitFont.detail).foregroundStyle(KitColor.text2).lineLimit(1)
                }
            }
            Spacer(minLength: KitSpace.s)
            if hover { actions.transition(.opacity) }
            trailing
        }
        .padding(.horizontal, KitSpace.l)
        .frame(height: height)
        .background(hover ? KitColor.well : Color.clear)
        .contentShape(Rectangle())
        .onHover { h in withAnimation(KitMotion.soft) { hover = h } }
    }
}

extension KitListRow where Actions == EmptyView {
    init(title: String, detail: String? = nil, height: CGFloat = 54,
         @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.init(title: title, detail: detail, height: height, leading: leading, trailing: trailing, actions: { EmptyView() })
    }
}

/// One-line empty state: a symbol and what to do.
struct KitEmptyState: View {
    let symbol: String
    let text: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 20, weight: .light)).foregroundStyle(KitColor.text3)
            Text(text).font(KitFont.body).foregroundStyle(KitColor.text2).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

// MARK: - Sections and rows (settings)

/// Settings group: a header and a recessed well of rows with hairlines between them.
struct KitSection<Content: View>: View {
    var title: String? = nil
    var footer: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(KitFont.header)
                    .foregroundStyle(KitColor.text2)
                    .padding(.leading, 2)
            }
            Group(subviews: content) { rows in
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        row
                        if row.id != rows.last?.id { KitDivider(inset: KitSpace.m) }
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: KitSpace.radius).fill(KitColor.well))
            if let footer {
                Text(footer)
                    .font(KitFont.detail)
                    .foregroundStyle(KitColor.text3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
            }
        }
    }
}

/// One settings row: optional bare SF Symbol, title, optional one-line detail, trailing control.
struct KitRow<Trailing: View>: View {
    let title: String
    var detail: String? = nil
    var symbol: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(KitColor.text2)
                    .frame(width: 18)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(KitFont.body).foregroundStyle(KitColor.text)
                if let detail {
                    Text(detail)
                        .font(KitFont.detail)
                        .foregroundStyle(KitColor.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: KitSpace.m)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(minHeight: 44)
    }
}

extension KitRow where Trailing == EmptyView {
    init(title: String, detail: String? = nil, symbol: String? = nil) {
        self.init(title: title, detail: detail, symbol: symbol) { EmptyView() }
    }
}

/// Row with a grip switch on the right.
struct KitToggleRow: View {
    let title: String
    var detail: String? = nil
    var symbol: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        KitRow(title: title, detail: detail, symbol: symbol) { KitSwitch(isOn: $isOn) }
            .accessibilityElement(children: .combine)
    }
}

// MARK: - Fields, keycaps, badges, meters

extension View {
    /// Plain text field look: `TextField("Name", text: $name).kitField()`
    func kitField() -> some View {
        textFieldStyle(.plain)
            .font(KitFont.body)
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: KitSpace.controlRadius).fill(KitColor.well))
            .overlay(RoundedRectangle(cornerRadius: KitSpace.controlRadius).strokeBorder(KitColor.line, lineWidth: 1))
    }
}

/// Shows a shortcut like "⌃⌥T" as small keys.
struct KitKeycaps: View {
    let keys: String
    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(String(key))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(KitColor.text2)
                    .frame(minWidth: 21, minHeight: 21)
                    .background(RoundedRectangle(cornerRadius: 4).fill(KitColor.well))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(KitColor.line, lineWidth: 1))
            }
        }
        .accessibilityLabel(keys)
    }
}

/// Status label with an LED: `KitBadge(text: "4 running")`. `lit: false` for a neutral count.
struct KitBadge: View {
    let text: String
    var lit = true
    var color: Color? = nil

    var body: some View {
        HStack(spacing: 6) {
            KitLed(on: lit, color: color)
            Text(text).font(KitFont.key).foregroundStyle(KitColor.text2).monospacedDigit()
        }
    }
}

/// Thin determinate bar for scans and exports.
struct KitProgress: View {
    let value: Double // 0...1
    var color: Color? = nil
    @Environment(\.kitAccent) private var accent

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(KitColor.well)
                Rectangle().fill(color ?? accent).frame(width: geo.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 3)
        .clipShape(RoundedRectangle(cornerRadius: 1.5))
        .accessibilityValue("\(Int((value * 100).rounded())) percent")
    }
}

/// LED level meter: a row of segments, lit up to `value`. Segments past `warn`/`danger` light amber/red.
/// Use for usage levels (Tally) and anything that is a level, not a task.
struct KitMeter: View {
    let value: Double // 0...1
    var segments = 24
    var warn: Double? = 0.7
    var danger: Double? = 0.9
    var color: Color? = nil
    @Environment(\.kitAccent) private var accent

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<segments, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1).fill(segmentColor(i))
            }
        }
        .frame(height: 8)
        .animation(KitMotion.list, value: value)
        .accessibilityElement()
        .accessibilityValue("\(Int((value * 100).rounded())) percent")
    }

    private func segmentColor(_ i: Int) -> Color {
        let position = Double(i + 1) / Double(segments)
        let lit = position <= value + 0.0001 || (i == 0 && value > 0)
        guard lit else { return KitColor.well }
        if let danger, position > danger { return KitColor.red }
        if let warn, position > warn { return KitColor.amber }
        return color ?? accent
    }
}

// MARK: - Sounds (few and quiet; Erik: "not too much sounds so it's annoying")

/// Bundle the files from `codex-specs/kit/Sounds/*.caf` into the app's Resources (folder reference "Sounds").
/// Play only for meaningful moments; never on hover, panel open or routine background work.
enum KitSound: String, CaseIterable {
    case switchFlip = "kit-switch"   // a KitSwitch is flipped by the user (very quiet)
    case thunk = "kit-thunk"         // a destructive action is confirmed (Stop, Move to Trash)
    case confirm = "kit-confirm"     // a user-started task finished (scan done, export done)
    case error = "kit-error"         // something the user asked for failed
    case powerOn = "kit-power-on"    // intro lights down / power on
    case powerOff = "kit-power-off"  // intro lights up / flies to the menu bar
    case drop = "kit-drop"           // files land on Ledge
    case chime = "kit-chime"         // something needs the user (Switchboard waiting)

    static let enabledKey = "kitSoundsEnabled"
    static let volumeKey = "kitSoundsVolume"

    @MainActor private static var cache: [KitSound: NSSound] = [:]

    /// Plays the sound if the user has sounds on (default on, volume 0.35) and macOS UI sounds are on.
    @MainActor static func play(_ sound: KitSound) {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: enabledKey) != nil, !defaults.bool(forKey: enabledKey) { return }
        if let ui = UserDefaults(suiteName: "com.apple.systemsound")?.object(forKey: "com.apple.sound.uiaudio.enabled") as? Bool, !ui { return }
        let volume = defaults.object(forKey: volumeKey) as? Double ?? 0.35
        let player: NSSound
        if let cached = cache[sound] {
            player = cached
        } else {
            guard let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "caf", subdirectory: "Sounds")
                    ?? Bundle.main.url(forResource: sound.rawValue, withExtension: "caf"),
                  let loaded = NSSound(contentsOf: url, byReference: true) else { return }
            cache[sound] = loaded
            player = loaded
        }
        player.stop()
        player.volume = Float(sound == .switchFlip ? volume * 0.6 : volume)
        player.play()
    }
}

// MARK: - Hot key field (records a shortcut; shows it as keycaps)

struct KitHotKey: Codable, Equatable, Sendable {
    var keyCode: UInt16
    var modifiers: UInt // NSEvent.ModifierFlags raw value, device-independent bits only
    var display: String // e.g. "⌥⌘H"
}

/// Click, press a shortcut with at least one of ⌘⌥⌃, done. Esc cancels, Delete clears.
struct KitHotKeyField: View {
    @Binding var hotKey: KitHotKey?
    @State private var recording = false
    @State private var monitor: Any?
    @Environment(\.kitAccent) private var accent

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            HStack(spacing: 6) {
                if recording {
                    KitLed(on: true)
                    Text("Press a shortcut").font(KitFont.key).foregroundStyle(KitColor.text2)
                } else if let hotKey {
                    KitKeycaps(keys: hotKey.display)
                } else {
                    Text("Record shortcut").font(KitFont.key).foregroundStyle(KitColor.text2)
                }
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 28)
            .background(RoundedRectangle(cornerRadius: KitSpace.controlRadius).fill(KitColor.well))
            .overlay(RoundedRectangle(cornerRadius: KitSpace.controlRadius)
                .strokeBorder(recording ? accent.opacity(0.7) : KitColor.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onDisappear { stop() }
        .accessibilityLabel(hotKey.map { "Shortcut \($0.display)" } ?? "Record shortcut")
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.keyCode == 53 { stop(); return nil }                 // Esc
            if event.keyCode == 51 { hotKey = nil; stop(); return nil }   // Delete
            guard !mods.intersection([.command, .option, .control]).isEmpty else { return nil }
            var text = ""
            if mods.contains(.control) { text += "⌃" }
            if mods.contains(.option) { text += "⌥" }
            if mods.contains(.shift) { text += "⇧" }
            if mods.contains(.command) { text += "⌘" }
            text += (event.charactersIgnoringModifiers ?? "").uppercased()
            hotKey = KitHotKey(keyCode: event.keyCode, modifiers: mods.rawValue, display: text)
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

// MARK: - Settings building blocks (every app's Settings window uses these)

/// The standard "Sounds" group: switch, volume, test key.
struct KitSoundSection: View {
    @AppStorage(KitSound.enabledKey) private var enabled = true
    @AppStorage(KitSound.volumeKey) private var volume = 0.35

    var body: some View {
        KitSection(title: "Sounds", footer: "Only for moments that matter: confirming, finishing, errors. Follows the macOS interface sounds setting.") {
            KitToggleRow(title: "Play sounds", isOn: $enabled)
            KitRow(title: "Volume") {
                HStack(spacing: 10) {
                    KitSlider(value: $volume, range: 0.05...1).frame(width: 140)
                    KitIconButton(symbol: "speaker.wave.2", help: "Play a test sound") { KitSound.play(.confirm) }
                }
            }
            .disabled(!enabled)
        }
    }
}

/// The standard About tab: icon, name, version, one line, links, licence and credits.
struct KitAboutView: View {
    let name: String
    let tagline: String
    var repoURL: URL? = nil
    var license = "MIT licence"
    var credits: [String] = ["Sounds: real recordings from Freesound, CC0"]

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(v) (\(b))"
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                .resizable().frame(width: 72, height: 72)
                .accessibilityHidden(true)
            VStack(spacing: 4) {
                Text(name).font(KitType.width(.system(size: 20, weight: .semibold))).foregroundStyle(KitColor.text)
                Text(version).font(KitFont.detail).foregroundStyle(KitColor.text2).monospacedDigit()
            }
            Text(tagline).font(KitFont.body).foregroundStyle(KitColor.text2).multilineTextAlignment(.center)
            if let repoURL {
                Button("View source") { NSWorkspace.shared.open(repoURL) }.buttonStyle(.kitSecondary)
            }
            VStack(spacing: 2) {
                Text(license)
                ForEach(credits, id: \.self) { Text($0) }
            }
            .font(KitFont.detail).foregroundStyle(KitColor.text3).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

/// Standard Settings window content: wide-type title, KitSegmented tabs, scrolling body.
/// Tabs: "General" first, app tabs in the middle, "About" last. Remembers the last tab.
struct KitSettings<Tab: Hashable & RawRepresentable, Content: View>: View where Tab.RawValue == String {
    let title: String
    let tabs: [(Tab, String)]
    @Binding var selection: Tab
    @ViewBuilder var content: (Tab) -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(KitFont.title).foregroundStyle(KitColor.text)
            KitSegmented(selection: $selection, options: tabs)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) { content(selection) }
                    .padding(.bottom, 8)
                    .id(selection)
                    .transition(.opacity.combined(with: .offset(y: 6)))
            }
            .scrollIndicators(.never)
            .animation(KitMotion.list, value: selection)
        }
        .padding(20)
        .frame(width: 520, height: 560)
        .background(KitColor.window)
    }
}
