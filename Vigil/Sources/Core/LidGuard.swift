import Foundation

struct LidGuard {
    let readClosed: () -> Bool?
    let readThermal: () -> ProcessInfo.ThermalState
    private(set) var closed: Bool?
    private var hotSince: TimeInterval?

    struct Action {
        var save = false, restore = false, end = false
        var remaining: TimeInterval?
    }

    init(readClosed: @escaping () -> Bool?, readThermal: @escaping () -> ProcessInfo.ThermalState) {
        self.readClosed = readClosed; self.readThermal = readThermal
    }

    mutating func sample(at now: TimeInterval, running: Bool, saver: Bool, heat: Bool, recovery: Bool = false) -> Action {
        let lid = readClosed(), thermal = readThermal()
        var action = Action()
        action.restore = recovery || lid == false || !saver
        action.save = !recovery && running && saver && closed == false && lid == true
        if let lid { closed = lid }
        if recovery { hotSince = nil }
        guard running, heat, lid == true, thermal == .serious || thermal == .critical else {
            hotSince = nil; return action
        }
        let start = hotSince ?? now
        hotSince = start
        let remaining = 120 - (now - start)
        if remaining <= 0 { action.end = true } else { action.remaining = remaining }
        return action
    }
}

protocol OutputMute {
    func defaultUID() -> String?
    func muted(_ uid: String) -> Bool?
    func setMuted(_ muted: Bool, uid: String) -> Bool
}

struct MuteRecord: Codable, Equatable {
    let uid: String, previouslyMuted: Bool
}

struct LidMute {
    let audio: OutputMute
    let file: URL

    var record: MuteRecord? {
        (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(MuteRecord.self, from: $0) }
    }

    func save() {
        guard record == nil, let uid = audio.defaultUID(), let previous = audio.muted(uid), !previous else { return }
        let entry = MuteRecord(uid: uid, previouslyMuted: previous)
        do { try JSONEncoder().encode(entry).write(to: file, options: .atomic) } catch { return }
        if !audio.setMuted(true, uid: uid) { clear() }
    }

    func restore() {
        guard let entry = record, let muted = audio.muted(entry.uid) else { return }
        if !muted || entry.previouslyMuted || audio.setMuted(false, uid: entry.uid) { clear() }
    }

    func relinquishIfUnmuted() {
        if let entry = record, audio.muted(entry.uid) == false { clear() }
    }

    private func clear() { try? FileManager.default.removeItem(at: file) }
}

