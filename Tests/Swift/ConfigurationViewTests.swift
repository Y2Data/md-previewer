import XCTest
import SwiftUI

@MainActor
final class ConfigurationViewTests: XCTestCase {
    func testEnglishAndChineseSettingsLayout() async throws {
        _ = NSApplication.shared
        let bundle = Bundle(for: ConfigurationViewTests.self)
        if let icon = bundle.url(forResource: "ConfigIcon", withExtension: "png"), let image = NSImage(contentsOf: icon) { NSApp.applicationIconImage = image }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        for language in [InterfaceLanguage.english, .chinese] {
            let model = SettingsModel(store: SettingsStore(directory: directory))
            model.settings.language = language
            let view = NSHostingView(rootView: ConfigurationView(model: model).preferredColorScheme(.light))
            let size = view.fittingSize
            XCTAssertEqual(size.width, 580, accuracy: 1)
            XCTAssertLessThan(size.height, 820, "The settings window should fit a laptop display.")
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = view
            view.frame = NSRect(origin: .zero, size: size)
            window.makeKeyAndOrderFront(nil)
            try await Task.sleep(for: .milliseconds(250))
            view.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
            attachment.name = "settings-" + language.rawValue
            attachment.lifetime = .keepAlways
            add(attachment)
            window.orderOut(nil)
            XCTAssertNil(model.errorMessage)
        }
    }
}
