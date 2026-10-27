import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct ClearMarkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = SettingsModel()
    var body: some Scene {
        Window("ClearMark", id: "settings") {
            ConfigurationView(model: model)
                .environment(\.locale, Locale(identifier: model.settings.language.resolved))
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .help) {
                Button(model.text("Quick Look Setup"), action: model.openExtensionSettings)
                Button(model.text("View on GitHub"), action: model.openProject)
            }
        }
    }
}
