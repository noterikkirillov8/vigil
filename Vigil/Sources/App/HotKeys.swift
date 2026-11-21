import Carbon
import AppKit

/// System-wide shortcuts through Carbon's hot keys: no permission needed, and the keys never
/// reach the app in front.
@MainActor
final class HotKeys {
    static let shared = HotKeys()
    private var handlers: [UInt32: @MainActor () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var installed = false

    struct Combo: Hashable {
        let keyCode: UInt32
        let modifiers: UInt32       // Carbon: cmdKey, optionKey, controlKey, shiftKey
    }

    func register(_ id: UInt32, _ combo: Combo, _ handler: @escaping @MainActor () -> Void) {
        installIfNeeded()
        unregister(id)
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x5647494C), id: id)   // "VGIL"
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return }
        refs[id] = ref
        handlers[id] = handler
    }

    func unregister(_ id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        handlers.removeValue(forKey: id)
    }

    fileprivate func fire(_ id: UInt32) { handlers[id]?() }

    private func installIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let id = hotKeyID.id
            // Carbon delivers hot keys on the main thread.
            MainActor.assumeIsolated { HotKeys.shared.fire(id) }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
