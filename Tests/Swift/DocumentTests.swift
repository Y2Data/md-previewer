import XCTest

final class DocumentTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    func testUTF8AndUTF16Documents() throws {
        let expected = "# こんにちは\n\nA clear thought. 🌿"
        for encoding: String.Encoding in [.utf8, .utf16] {
            let url = directory.appendingPathComponent("note.md")
            try expected.data(using: encoding)!.write(to: url)
            let document = try DocumentContent.read(url)
            XCTAssertEqual(document.text, expected)
            XCTAssertEqual(document.title, "note.md")
            XCTAssertEqual(document.readingMinutes, 1)
        }
    }

    func testRejectsBinaryAndUnsupportedFiles() throws {
        let binary = directory.appendingPathComponent("binary.md")
        try Data([0, 1, 2, 3]).write(to: binary)
        XCTAssertThrowsError(try DocumentContent.read(binary))
        let unsupported = directory.appendingPathComponent("script.js")
        try Data("hello".utf8).write(to: unsupported)
        XCTAssertThrowsError(try DocumentContent.read(unsupported))
        let invalid = directory.appendingPathComponent("invalid.md")
        try Data([0xFF, 0xAB, 0xCD]).write(to: invalid)
        XCTAssertThrowsError(try DocumentContent.read(invalid))
    }

    func testRejectsOversizedFiles() throws {
        let url = directory.appendingPathComponent("large.md")
        try Data(repeating: 65, count: DocumentContent.maximumBytes + 1).write(to: url)
        XCTAssertThrowsError(try DocumentContent.read(url))
    }

    func testResourceContainmentAndSymlinks() throws {
        let root = directory.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let outside = directory.appendingPathComponent("secret.png")
        try Data("secret".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape.png"), withDestinationURL: outside)
        XCTAssertThrowsError(try PreviewResources.resolve("../secret.png", inside: root))
        XCTAssertThrowsError(try PreviewResources.resolve("escape.png", inside: root))
        XCTAssertThrowsError(try PreviewResources.resolve("../../images-other/secret.png", inside: root))
        XCTAssertEqual(try PreviewResources.resolve("safe image.png", inside: root), root.appendingPathComponent("safe image.png"))
    }

    func testReadingTimeRoundsUp() {
        let text = Array(repeating: "word", count: 221).joined(separator: " ")
        let document = DocumentContent(url: nil, text: text, title: "Test")
        XCTAssertEqual(document.wordCount, 221)
        XCTAssertEqual(document.readingMinutes, 2)
    }
}
