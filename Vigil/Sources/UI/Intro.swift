import AppKit
import Observation
import SwiftUI

/// Three short scenes, fades only. The clock lives in `IntroFlow`; this class only ticks it.
@MainActor
@Observable
final class IntroModel {
    static let titles = ["Pick how long", "Close the lid, it keeps going", "It always ends on time"]
    static let lines = ["From 30 minutes to 8 hours, or your own length. There is no open-ended switch.",
                        "Vigil keeps the Mac awake with the lid shut, so your agents keep running.",
                        "The night strip goes dark as time runs out. Then sleep comes back."]
    var scene: Int
    var t: Double
    @ObservationIgnored private var flow = IntroFlow(durations: [4, 4, 4])
    @ObservationIgnored private var started = Date()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored var onClose: () -> Void = {}

    /// `scene` and `t` are for QA frames.
    init(scene: Int = 0, t: Double = 0) { self.scene = scene; self.t = t }

    func start() {
        started = Date()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
    private func now() -> Double { Date().timeIntervalSince(started) }
    private func tick() { flow.tick(now: now()); pull() }
    func next() { flow.next(now: now()); pull() }
    func back() { flow.back(now: now()); pull() }
    func finish() { flow.close(); timer?.invalidate(); timer = nil }
    func close() { finish(); onClose() }
    private func pull() {
        withAnimation(.easeInOut(duration: 0.3)) { scene = flow.scene }
        t = flow.time(now: now())
        if flow.closed { onClose() }
    }
    var isLast: Bool { scene == IntroModel.titles.count - 1 }
}

struct IntroView: View {
    @Bindable var intro: IntroModel

    var body: some View {
        VStack(spacing: 0) {
            ZStack { stage.id(intro.scene).transition(.opacity) }
                .frame(height: 300).frame(maxWidth: .infinity)
            VStack(spacing: 6) {
                Text(IntroModel.titles[intro.scene]).font(.system(size: 17, weight: .semibold)).foregroundStyle(KitColor.text)
                Text(IntroModel.lines[intro.scene]).font(KitFont.body).foregroundStyle(KitColor.text2).multilineTextAlignment(.center)
                    .frame(maxWidth: 420, minHeight: 36, alignment: .top)
            }.id(intro.scene).transition(.opacity)
            Spacer(minLength: 0)
            HStack {
                Button("Skip") { intro.close() }.buttonStyle(.kitQuiet).opacity(intro.isLast ? 0 : 1)
                Spacer()
                HStack(spacing: 8) { ForEach(0..<3, id: \.self) { KitLed(on: $0 == intro.scene) } }
                Spacer()
                if intro.isLast { Button("Get started") { intro.close() }.buttonStyle(.kitPrimary) }
                else { Button("Next") { intro.next() }.buttonStyle(.kitSecondary) }
            }.padding(.horizontal, 20).padding(.bottom, 20)
        }
        .frame(width: 640, height: 440)
        .background(KitColor.window)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(KitColor.line, lineWidth: 1))
        .kitAccent(Prefs.accent)
    }

    @ViewBuilder private var stage: some View {
        let t = intro.t
        switch intro.scene {
        case 0:
            VStack(spacing: 20) {
                KitSegmented(selection: .constant(t < 1.2 ? 60 : 120), options: Presets.minutes.map { ($0, Presets.label($0)) })
                    .animation(KitMotion.snap, value: t < 1.2).frame(width: 330)
                Text("Start").font(KitFont.button).foregroundStyle(KitColor.window).frame(width: 330, height: 32)
                    .background(RoundedRectangle(cornerRadius: KitSpace.controlRadius).fill(KitColor.text))
            }
        case 1:
            let left = 6127 - Int(t)
            VStack(alignment: .leading, spacing: 14) {
                Text(Session.countdown(Double(left))).font(KitFont.figure(48)).foregroundStyle(KitColor.text).kitRollingNumber(left)
                NightStrip(lit: 21)
                HStack(spacing: 6) {
                    Spacer(); KitLed(on: t > 0.8)
                    Text(t > 0.8 ? "Lid mode on" : "Lid mode off").font(KitFont.detail).foregroundStyle(KitColor.text2)
                }
            }.frame(width: 330)
        default:
            let lit = max(0, 24 - Int(t * 6))
            VStack(alignment: .leading, spacing: 14) {
                Text(lit == 0 ? "0:00" : Session.countdown(Double(lit) * 300)).font(KitFont.figure(48)).foregroundStyle(KitColor.text).kitRollingNumber(lit)
                NightStrip(lit: lit)
                HStack(spacing: 6) {
                    Text("Ends at 21:34").font(KitFont.detail).foregroundStyle(KitColor.text2)
                    Spacer(); KitLed(on: lit > 0)
                    Text(lit > 0 ? "Awake" : "Sleep is back").font(KitFont.detail).foregroundStyle(KitColor.text2)
                }
            }.frame(width: 330)
        }
    }
}

@MainActor
final class IntroController {
    static let seenKey = "vigilIntroSeen"
    static var seen: Bool { Prefs.store.bool(forKey: seenKey) }

    private let presenter = IntroPresenter()
    private var intro: IntroModel?
    var isShowing: Bool { presenter.isShowing }

    func show() {
        Prefs.store.set(true, forKey: Self.seenKey)    // seen as soon as it is shown: a failed intro never repeats
        if presenter.isShowing { presenter.focus(); return }
        let m = IntroModel()
        intro = m
        m.onClose = { [weak self] in self?.presenter.close() }
        presenter.onClose = { [weak m] in m?.finish() }
        presenter.onNext = { [weak m] in m?.next() }
        presenter.onBack = { [weak m] in m?.back() }
        presenter.show(IntroView(intro: m), size: CGSize(width: 640, height: 440))
        m.start()
    }
}
