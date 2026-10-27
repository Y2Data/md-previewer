import WebKit
import UniformTypeIdentifiers
import ImageIO

final class ResourceSchemeHandler: NSObject, WKURLSchemeHandler {
    var documentDirectory: URL?
    private var imageBytes = 0
    private var imageCount = 0
    private var decodedPixels = 0
    private var servedImages = Set<URL>()
    private let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "svg", "avif", "ico"]

    func resetBudget() { imageBytes = 0; imageCount = 0; decodedPixels = 0; servedImages.removeAll() }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        do {
            guard let request = urlSchemeTask.request.url else { throw DocumentError.unsafeResource }
            let isImageAlias = request.host == "bundle" && request.path.hasPrefix("/_images/")
            let isDocument = request.host == "document" || isImageAlias
            let root: URL
            if isDocument, let directory = documentDirectory { root = directory }
            else if request.host == "bundle" { root = PreviewResources.root }
            else { throw DocumentError.unsafeResource }
            let path = isImageAlias ? String(request.path.dropFirst("/_images/".count)) : String(request.path.drop(while: { $0 == "/" }))
            let file = try PreviewResources.resolve(path, inside: root)
            let ext = file.pathExtension.lowercased()
            let alreadyServed = servedImages.contains(file)
            if isDocument {
                guard imageExtensions.contains(ext) else { throw DocumentError.unsafeResource }
                let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 12 * 1_024 * 1_024 else { throw DocumentError.unsafeResource }
                if ext == "svg", size > 1_024 * 1_024 { throw DocumentError.unsafeResource }
                if !alreadyServed {
                    guard imageCount < 100, imageBytes + size <= 32 * 1_024 * 1_024 else { throw DocumentError.unsafeResource }
                    imageBytes += size
                    imageCount += 1
                }
            }
            var data = try Data(contentsOf: file, options: .mappedIfSafe)
            var mime = ["js": "text/javascript", "css": "text/css", "html": "text/html", "svg": "image/svg+xml", "woff2": "font/woff2", "woff": "font/woff", "ttf": "font/ttf"][ext]
                ?? UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
            if isDocument, ext != "svg" {
                guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                      let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 2048, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { throw DocumentError.unsafeResource }
                let pixels = thumbnail.width * thumbnail.height
                if !alreadyServed {
                    guard decodedPixels + pixels <= 24_000_000 else { throw DocumentError.unsafeResource }
                    decodedPixels += pixels
                }
                let output = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { throw DocumentError.unsafeResource }
                CGImageDestinationAddImage(destination, thumbnail, nil)
                guard CGImageDestinationFinalize(destination) else { throw DocumentError.unsafeResource }
                data = output as Data
                mime = "image/png"
            }
            if isDocument { servedImages.insert(file) }
            urlSchemeTask.didReceive(URLResponse(url: request, mimeType: mime, expectedContentLength: data.count, textEncodingName: mime.hasPrefix("text/") ? "utf-8" : nil))
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch { urlSchemeTask.didFailWithError(error) }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
