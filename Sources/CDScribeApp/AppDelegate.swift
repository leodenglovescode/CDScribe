// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?
    private var mainWindow: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        // A file-associated app can launch without SwiftUI presenting its scene.
        // Keep the same real review view and model available in that case.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, let model = self.model else { return }
            if let existing = NSApplication.shared.windows.first(where: { $0.title == "CDScribe" && $0.isVisible }) {
                existing.makeKeyAndOrderFront(nil)
            } else {
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 790), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
                window.title = "CDScribe"; window.minSize = NSSize(width: 1000, height: 670)
                window.isReleasedWhenClosed = false
                window.contentView = NSHostingView(rootView: MainView(model: model))
                window.center(); window.makeKeyAndOrderFront(nil)
                self.mainWindow = window
            }
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, let mainWindow { mainWindow.makeKeyAndOrderFront(nil); sender.activate(ignoringOtherApps: true) }
        return true
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if model?.busy == true { model?.attemptQuit(); return .terminateCancel }
        model?.invalidate(); return .terminateNow
    }
}
