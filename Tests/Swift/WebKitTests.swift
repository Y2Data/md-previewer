import XCTest
import WebKit
import PDFKit
@testable import ClearMark

@MainActor
final class WebKitTests: XCTestCase {
    func testBundledRendererInWebKit() async throws {
        let controller = PreviewController()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 760), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = controller.webView
        controller.webView.frame = NSRect(x: 0, y: 0, width: 900, height: 760)
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        let loaded = expectation(description: "Bundled preview loads")
        var fulfilled = false
        controller.onError = { message in
            XCTFail(message)
            if !fulfilled { fulfilled = true; loaded.fulfill() }
        }
        controller.onOutline = { items in
            if !fulfilled, items.contains(where: { $0.title == "Native WebKit" }) { fulfilled = true; loaded.fulfill() }
        }
        controller.display(DocumentContent(url: nil, text: "# Native WebKit", title: "Test.md"))
        await fulfillment(of: [loaded], timeout: 20)
        let source = "# Verified\n\n<script>window.compromised = true</script>\n\n$x^2$\n\n```mermaid\ngraph LR\n A-->B\n```\n\n```swift\nlet answer = 42\n```"
        _ = try await controller.webView.callAsyncJavaScript("await window.ClearMark.render(source); return true", arguments: ["source": source], in: nil, contentWorld: .page)
        let result = try await controller.webView.evaluateJavaScript("({title: document.querySelector('h1').textContent, math: document.querySelectorAll('.katex').length, diagrams: document.querySelectorAll('.mermaid-diagram svg').length, highlighted: document.querySelectorAll('.hljs-keyword').length, safe: !window.compromised && !document.querySelector('#article script')})") as! [String: Any]
        XCTAssertEqual(result["title"] as? String, "Verified")
        XCTAssertEqual(result["math"] as? Int, 1)
        XCTAssertEqual(result["diagrams"] as? Int, 1)
        XCTAssertGreaterThan(result["highlighted"] as? Int ?? 0, 0)
        XCTAssertEqual(result["safe"] as? Bool, true)
        let html = try await controller.webView.callAsyncJavaScript("return await window.ClearMark.exportHTML()", arguments: [:], in: nil, contentWorld: .page) as! String
        XCTAssertTrue(html.contains("<math"))
        XCTAssertFalse(html.contains("<script"))
        XCTAssertFalse(html.contains("clearmark://"))
        let pdfData = try await controller.pdfData()
        let pdf = try XCTUnwrap(PDFDocument(data: pdfData))
        XCTAssertGreaterThan(pdf.pageCount, 0)
        XCTAssertTrue(pdf.string?.contains("Verified") == true)
    }

    func testLocalImagesArePortableAndConfined() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aPioAAAAASUVORK5CYII=")!
        try png.write(to: directory.appendingPathComponent("pixel.png"))
        let controller = PreviewController()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 760), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = controller.webView
        controller.webView.frame = NSRect(x: 0, y: 0, width: 900, height: 760)
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        let loaded = expectation(description: "Image preview loads")
        controller.onError = { message in XCTFail(message); loaded.fulfill() }
        controller.onOutline = { _ in loaded.fulfill() }
        controller.display(DocumentContent(url: directory.appendingPathComponent("test.md"), text: "# Images\n\n![Pixel](pixel.png)", title: "Images"))
        await fulfillment(of: [loaded], timeout: 20)
        _ = try await controller.webView.callAsyncJavaScript("const image = document.querySelector('img'); image.loading = 'eager'; await image.decode(); return image.naturalWidth", arguments: [:], in: nil, contentWorld: .page)
        let html = try await controller.webView.callAsyncJavaScript("return await window.ClearMark.exportHTML()", arguments: [:], in: nil, contentWorld: .page) as! String
        XCTAssertTrue(html.contains("data:image/png;base64,"))
        XCTAssertFalse(html.contains("Image not included in export"))
    }
}
