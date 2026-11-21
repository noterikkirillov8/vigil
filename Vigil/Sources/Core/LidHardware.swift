import CoreAudio
import Foundation
import IOKit
import IOKit.pwr_mgt

final class Clamshell {
    private static let clamshellStateChange: UInt32 = (0x38 << 26) | (13 << 14) | 0x100
    private let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
    private let port = IONotificationPortCreate(kIOMainPortDefault)
    private var interest: io_object_t = 0
    private let changed: @MainActor () -> Void

    init(changed: @escaping @MainActor () -> Void) {
        self.changed = changed
        guard root != 0, let port else { return }
        IONotificationPortSetDispatchQueue(port, .main)
        IOServiceAddInterestNotification(port, root, kIOGeneralInterest, { context, _, message, _ in
            guard message == Clamshell.clamshellStateChange, let context else { return }
            let changed = Unmanaged<Clamshell>.fromOpaque(context).takeUnretainedValue().changed
            MainActor.assumeIsolated { changed() }
        }, Unmanaged.passUnretained(self).toOpaque(), &interest)
    }

    func read() -> Bool? {
        guard root != 0 else { return nil }
        return IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool
    }

    deinit {
        if interest != 0 { IOObjectRelease(interest) }
        if let port { IONotificationPortDestroy(port) }
        if root != 0 { IOObjectRelease(root) }
    }
}

struct CoreOutput: OutputMute {
    private let system = AudioObjectID(kAudioObjectSystemObject)
    private func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    func defaultUID() -> String? {
        var device = AudioDeviceID(0), size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var property = address(kAudioHardwarePropertyDefaultOutputDevice)
        guard AudioObjectGetPropertyData(system, &property, 0, nil, &size, &device) == noErr else { return nil }
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout.size(ofValue: uid)); property = address(kAudioDevicePropertyDeviceUID)
        guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &uid) == noErr else { return nil }
        return uid?.takeRetainedValue() as String?
    }

    private func device(_ uid: String) -> AudioDeviceID? {
        var property = address(kAudioHardwarePropertyTranslateUIDToDevice), device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout.size(ofValue: device))
        let string = uid as CFString
        return withExtendedLifetime(string) {
            var qualifier = Unmanaged.passUnretained(string)
            let status = AudioObjectGetPropertyData(system, &property, UInt32(MemoryLayout.size(ofValue: qualifier)), &qualifier, &size, &device)
            return status == noErr && device != kAudioObjectUnknown ? device : nil
        }
    }

    func muted(_ uid: String) -> Bool? {
        guard let device = device(uid) else { return nil }
        var property = address(kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput), value: UInt32 = 0
        var size = UInt32(MemoryLayout.size(ofValue: value))
        guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }

    func setMuted(_ muted: Bool, uid: String) -> Bool {
        guard let device = device(uid) else { return false }
        var property = address(kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput), value: UInt32 = muted ? 1 : 0
        return AudioObjectSetPropertyData(device, &property, 0, nil, UInt32(MemoryLayout.size(ofValue: value)), &value) == noErr
    }

    func watchMute(_ uid: String, changed: @escaping @MainActor @Sendable () -> Void) -> (() -> Void)? {
        guard let device = device(uid) else { return nil }
        return watch(device, address(kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput), changed)
    }

    func watchDevices(_ changed: @escaping @MainActor @Sendable () -> Void) -> (() -> Void)? {
        watch(system, address(kAudioHardwarePropertyDevices), changed)
    }

    private func watch(_ device: AudioObjectID, _ address: AudioObjectPropertyAddress, _ changed: @escaping @MainActor @Sendable () -> Void) -> (() -> Void)? {
        var property = address
        let listener: AudioObjectPropertyListenerBlock = { _, _ in MainActor.assumeIsolated { changed() } }
        guard AudioObjectAddPropertyListenerBlock(device, &property, .main, listener) == noErr else { return nil }
        return { AudioObjectRemovePropertyListenerBlock(device, &property, .main, listener) }
    }
}
