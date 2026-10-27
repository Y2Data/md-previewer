import XCTest

final class SettingsTests: XCTestCase {
    func testSettingsSurviveASeparateReader() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = SettingsStore(directory: directory)
        var settings = PreviewSettings()
        settings.language = .chinese
        settings.theme = .paper
        settings.fontSize = 21
        settings.renderDiagrams = false
        try writer.save(settings)
        let reader = SettingsStore(directory: directory)
        XCTAssertEqual(reader.load(), settings)
        XCTAssertEqual(reader.load().javascriptOptions["language"] as? String, "zh-Hans")
        XCTAssertEqual(reader.load().javascriptOptions["renderDiagrams"] as? Bool, false)
    }

    func testMissingAndMalformedSettingsFallBackSafely() throws {
        XCTAssertEqual(SettingsStore(directory: nil).load(), PreviewSettings())
        XCTAssertThrowsError(try SettingsStore(directory: nil).save(PreviewSettings()))
        let partial = try JSONDecoder().decode(PreviewSettings.self, from: Data("{\"fontSize\":999,\"theme\":\"unknown\"}".utf8))
        XCTAssertEqual(partial.fontSize, 24)
        XCTAssertEqual(partial.theme, .system)
        XCTAssertTrue(partial.renderDiagrams)
    }

    func testBothInterfaceLanguages() {
        XCTAssertEqual(L10n.text("Language", language: .chinese), "语言")
        XCTAssertEqual(L10n.text("Language", language: .english), "Language")
        XCTAssertEqual(L10n.text("Quick Look Setup", language: .chinese), "设置快速预览")
        XCTAssertEqual(L10n.text("Future unknown key", language: .chinese), "Future unknown key")
    }
}
