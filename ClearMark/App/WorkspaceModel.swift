import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers
import WebKit

enum ReadingMode: String, CaseIterable { case read = "Read", split = "Split", source = "Source" }
enum ReaderTheme: String, CaseIterable { case system = "System", light = "Light", dark = "Dark", paper = "Paper" }

struct RecentDocument: Identifiable, Codable {
    var id: String { path }
    let name: String
    let path: String
    let bookmark: Data
}

@MainActor
final class WorkspaceModel: ObservableObject {
    @Published private(set) var document: DocumentContent
    @Published private(set) var outline: [OutlineItem] = []
    @Published private(set) var recents: [RecentDocument] = []
    @Published var mode: ReadingMode = .read
    @Published var theme: ReaderTheme = .system { didSet { refreshPreview(); UserDefaults.standard.set(theme.rawValue, forKey: "readerTheme") } }
    @Published var fontSize: Double = 17 { didSet { refreshPreview(); UserDefaults.standard.set(fontSize, forKey: "readerFontSize") } }
    @Published var wide = false { didSet { refreshPreview() } }
    @Published var showFind = false
    @Published var query = ""
    @Published var errorMessage: String?
    @Published var reloadIssue: String?
    @Published var exporting = false
    let preview = PreviewController()
    private var scopedURL: URL?
    private var imageFolder: URL?
    private var timer: Timer?
    private var fileStamp: String?

    init() {
        let welcome = (try? String(contentsOf: PreviewResources.root.appendingPathComponent("Welcome.md"), encoding: .utf8)) ?? "# Welcome to ClearMark\nOpen a Markdown document to begin."
        document = DocumentContent(url: nil, text: welcome, title: "Welcome to ClearMark")
        if let saved = UserDefaults.standard.string(forKey: "readerTheme"), let value = ReaderTheme(rawValue: saved) { theme = value }
        let savedSize = UserDefaults.standard.double(forKey: "readerFontSize")
        if savedSize > 0 { fontSize = min(24, max(13, savedSize)) }
        if let data = UserDefaults.standard.data(forKey: "recentDocuments"), let saved = try? JSONDecoder().decode([RecentDocument].self, from: data) { recents = saved }
        preview.onOutline = { [weak self] in self?.outline = $0 }
        preview.onLink = { [weak self] in self?.openLink($0) }
        preview.onError = { [weak self] in self?.errorMessage = $0 }
        refreshPreview()
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reloadIfChanged() }
        }
    }

    func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, UTType(importedAs: "net.daringfireball.markdown")]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Open a Markdown document"
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    func open(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        do {
            let next = try DocumentContent.read(url)
            scopedURL?.stopAccessingSecurityScopedResource()
            imageFolder?.stopAccessingSecurityScopedResource()
            imageFolder = nil
            scopedURL = accessed ? url : nil
            document = next
            outline = []
            fileStamp = stamp(for: url)
            reloadIssue = nil
            query = ""
            remember(url)
            preview.webView.evaluateJavaScript("window.scrollTo(0, 0)", completionHandler: nil)
            refreshPreview()
        } catch {
            if accessed { url.stopAccessingSecurityScopedResource() }
            errorMessage = error.localizedDescription
        }
    }

    func openRecent(_ recent: RecentDocument) {
        do {
            var stale = false
            let url = try URL(resolvingBookmarkData: recent.bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
            open(url)
        } catch { errorMessage = "This recent document is no longer available. Open it again with File → Open." }
    }

    func clearRecents() { recents = []; UserDefaults.standard.removeObject(forKey: "recentDocuments") }

    func allowImageFolder() {
        guard let directory = document.url?.deletingLastPathComponent() else { return }
        let panel = NSOpenPanel()
        panel.title = "Allow local images"
        panel.message = "Choose this document’s folder to let ClearMark display its local images."
        panel.directoryURL = directory
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            guard url.resolvingSymlinksInPath().standardizedFileURL == directory.resolvingSymlinksInPath().standardizedFileURL else {
                errorMessage = "Select the folder containing this Markdown document."
                return
            }
            imageFolder?.stopAccessingSecurityScopedResource()
            imageFolder = url.startAccessingSecurityScopedResource() ? url : nil
            refreshPreview()
        }
    }

    func refreshPreview() { preview.display(document, theme: theme.rawValue.lowercased(), fontSize: fontSize, wide: wide) }
    func adjustFont(by amount: Double) { fontSize = min(24, max(13, fontSize + amount)) }
    func find(backwards: Bool = false) { preview.find(query, backwards: backwards) }

    func copyMarkdown() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(document.text, forType: .string)
    }

    func exportPDF() {
        if mode == .source { mode = .read }
        let panel = savePanel(type: .pdf)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        exporting = true
        Task {
            defer { exporting = false }
            do { try await preview.pdfData().write(to: url, options: .atomic) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    func printDocument() {
        guard let window = NSApp.mainWindow else { return }
        if mode == .source { mode = .read }
        let operation = preview.webView.printOperation(with: .shared)
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    func exportHTML() {
        let panel = savePanel(type: .html)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        exporting = true
        preview.webView.callAsyncJavaScript("return await window.ClearMark.exportHTML()", arguments: [:], in: nil, in: .page) { [weak self] result in
            guard let self else { return }
            defer { self.exporting = false }
            do {
                let value = try result.get()
                guard let html = value as? String else { throw CocoaError(.fileWriteUnknown) }
                try html.write(to: url, atomically: true, encoding: .utf8)
            } catch { self.errorMessage = error.localizedDescription }
        }
    }

    private func savePanel(type: UTType) -> NSSavePanel {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = (document.title as NSString).deletingPathExtension + "." + (type.preferredFilenameExtension ?? "")
        return panel
    }

    private func remember(_ url: URL) {
        guard let bookmark = try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        recents.removeAll { $0.path == url.path }
        recents.insert(RecentDocument(name: url.lastPathComponent, path: url.path, bookmark: bookmark), at: 0)
        recents = Array(recents.prefix(10))
        if let data = try? JSONEncoder().encode(recents) { UserDefaults.standard.set(data, forKey: "recentDocuments") }
    }

    private func stamp(for url: URL) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return "\(attrs[.modificationDate] ?? "")-\(attrs[.size] ?? "")-\(attrs[.systemFileNumber] ?? "")"
    }

    private func reloadIfChanged() {
        guard let url = document.url else { return }
        guard let current = stamp(for: url) else { reloadIssue = "File unavailable · showing last preview"; return }
        guard current != fileStamp else { reloadIssue = nil; return }
        do {
            document = try DocumentContent.read(url)
            fileStamp = current
            reloadIssue = nil
            refreshPreview()
        } catch { reloadIssue = "Couldn’t reload · showing last preview" }
    }

    private func openLink(_ href: String) {
        guard let url = URL(string: href) else { return }
        if ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") {
            NSWorkspace.shared.open(url)
        } else if url.scheme == "clearmark", url.host == "document", let directory = document.url?.deletingLastPathComponent() {
            do {
                let file = try PreviewResources.resolve(String(url.path.drop(while: { $0 == "/" })), inside: directory)
                open(file)
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
