import AppKit
import SwiftUI

@MainActor
final class SettingsModel: ObservableObject {
    @Published var settings: PreviewSettings {
        didSet {
            do { try store.save(settings) }
            catch { errorMessage = text("Settings could not be saved. Install the signed app in Applications and try again.") }
        }
    }
    @Published var errorMessage: String?
    private let store: SettingsStore
    init(store: SettingsStore = SettingsStore()) {
        self.store = store
        settings = store.load()
    }
    func text(_ key: String) -> String { L10n.text(key, language: settings.language) }
    func reset() { settings = PreviewSettings() }
    func openExtensionSettings() {
        let link: String
        if #available(macOS 15, *) { link = "x-apple.systempreferences:com.apple.LoginItems-Settings.extension" }
        else { link = "x-apple.systempreferences:com.apple.ExtensionsPreferences" }
        NSWorkspace.shared.open(URL(string: link)!)
    }
    func openProject() { NSWorkspace.shared.open(URL(string: "https://github.com/Y2Data/md-previewer")!) }
}
