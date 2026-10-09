// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import CDScribeCore

@main
struct CDScribeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model: AppModel
    @AppStorage("appearance") private var appearance = "System"
    init() {
        let model = AppModel()
        _model = State(initialValue: model)
        delegate.model = model
    }
    var body: some Scene {
        Window("CDScribe", id: "main") {
            MainView(model: model)
                .preferredColorScheme(appearance == "Dark" ? .dark : appearance == "Light" ? .light : nil)
                .frame(minWidth: 1000, minHeight: 670)
        }
        .defaultSize(width: 1180, height: 790)
        .defaultLaunchBehavior(.presented)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit CDScribe") { model.attemptQuit() }.keyboardShortcut("q")
            }
            CommandGroup(replacing: .newItem) {
                Button("Open FLAC Files…") { model.openFiles() }.keyboardShortcut("o").disabled(model.busy)
                Button("Open Album Folder…") { model.openFiles(folder: true) }.keyboardShortcut("o", modifiers: [.command, .shift]).disabled(model.busy)
            }
            CommandMenu("Disc") {
                Button("CD-Text Preview") { model.showPreview = true }.keyboardShortcut("p", modifiers: [.command, .shift])
                Button("ISRC Preview") { model.showISRCReview = true }.disabled(!model.hasAlbum)
                Button("Prepare Audio Without Burning") { model.prepare() }.disabled(!model.hasAlbum || model.busy)
                Button("Burn Audio CD") { model.burn() }.disabled(!model.canBurn)
                Divider()
                Button("Diagnostics") { model.showDiagnostics = true }.keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }
        Settings { SettingsView(model: model).frame(width: 610) }
    }
}
