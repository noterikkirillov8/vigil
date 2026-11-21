import Foundation

/// The first-launch intro as a pure state machine. One clock: the owner calls `tick(now:)` from a single timer,
/// and every scene reads its local time from `time(now:)`. No timers, no async work in here, so Next, Back,
/// Skip and close can never leave stale work behind.
struct IntroFlow {
    let durations: [Double]          // seconds each scene plays before auto-advancing (the last one waits)
    private(set) var scene = 0
    private(set) var sceneStart: Double
    private(set) var generation = 0  // bumps on every scene change
    private(set) var closed = false
    private(set) var seen = false    // set by close() and by markSeen(); the owner persists it

    init(durations: [Double], now: Double = 0) { self.durations = durations; sceneStart = now }

    var count: Int { durations.count }
    var isLast: Bool { scene == count - 1 }
    func time(now: Double) -> Double { max(0, now - sceneStart) }

    mutating func markSeen() { seen = true }

    /// Auto-advance. Returns true when the scene changed.
    @discardableResult
    mutating func tick(now: Double) -> Bool {
        guard !closed, !isLast, now - sceneStart >= durations[scene] else { return false }
        go(scene + 1, now)
        return true
    }
    mutating func next(now: Double) { if closed { return }; if isLast { close() } else { go(scene + 1, now) } }
    mutating func back(now: Double) { if closed || scene == 0 { return }; go(scene - 1, now) }
    /// Skip, Esc, the close button, Cmd-W and "Get started" all end here.
    mutating func close() { closed = true; seen = true }

    private mutating func go(_ i: Int, _ now: Double) { scene = i; sceneStart = now; generation += 1 }
}
