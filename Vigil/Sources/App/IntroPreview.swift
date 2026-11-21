import AppKit
import SwiftUI

/// `Vigil -intro-preview <dir>`: start, middle and end frame of every intro scene, off-screen only.
@MainActor
enum IntroPreview {
    static func runIfAsked() -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-intro-preview"), i + 1 < args.count else { return false }
        NSApp.setActivationPolicy(.prohibited)
        let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        Prefs.register()
        for scene in 0..<IntroModel.titles.count {
            for (label, t) in [("start", 0.2), ("middle", 2.0), ("end", 3.8)] {
                let host = NSHostingView(rootView: IntroView(intro: IntroModel(scene: scene, t: t)).padding(24).background(Color(hex: 0x2A2B2E)).environment(\.colorScheme, .dark))
                QA.capture(host, dark: true, name: "intro-\(scene + 1)-\(label)", dir: dir)
            }
        }
        NSApp.terminate(nil)
        return true
    }
}
