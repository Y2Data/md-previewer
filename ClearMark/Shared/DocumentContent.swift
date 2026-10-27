import Foundation
import UniformTypeIdentifiers

enum DocumentError: LocalizedError {
    case tooLarge, unsupportedEncoding, notMarkdown, unsafeResource

    var errorDescription: String? {
        switch self {
        case .tooLarge: return L10n.text("This document is larger than 8 MB. Open a smaller file to keep previews responsive.")
        case .unsupportedEncoding: return L10n.text("This file isn’t readable text. Save it as UTF-8 or UTF-16 and try again.")
        case .notMarkdown: return L10n.text("Choose a Markdown or plain text document.")
        case .unsafeResource: return L10n.text("This resource is outside the document’s folder or cannot be previewed.")
        }
    }
}

struct DocumentContent {
    static let maximumBytes = 8 * 1_024 * 1_024
    static let extensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn", "mdx", "txt"]
    let url: URL?
    let text: String
    let title: String

    static func read(_ url: URL) throws -> DocumentContent {
        guard extensions.contains(url.pathExtension.lowercased()) else { throw DocumentError.notMarkdown }
        let attributes = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard attributes.isRegularFile == true else { throw DocumentError.notMarkdown }
        guard (attributes.fileSize ?? 0) <= maximumBytes else { throw DocumentError.tooLarge }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else { throw DocumentError.tooLarge }
        let text: String?
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            text = String(data: data, encoding: .utf16)
        } else {
            text = String(data: data, encoding: .utf8)
        }
        guard let text, !text.contains("\0") else { throw DocumentError.unsupportedEncoding }
        return DocumentContent(url: url, text: text, title: url.lastPathComponent)
    }

    var wordCount: Int { text.split(whereSeparator: { $0.isWhitespace }).count }
    var readingMinutes: Int { max(1, Int(ceil(Double(wordCount) / 220))) }
}

enum PreviewResources {
    static var root: URL { Bundle(for: PreviewBundle.self).resourceURL!.appendingPathComponent("Resources", isDirectory: true) }

    static func resolve(_ path: String, inside root: URL) throws -> URL {
        let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let candidate = canonicalRoot.appendingPathComponent(path).resolvingSymlinksInPath().standardizedFileURL
        guard candidate.path.hasPrefix(canonicalRoot.path + "/") else { throw DocumentError.unsafeResource }
        return candidate
    }
}

private final class PreviewBundle: NSObject {}
