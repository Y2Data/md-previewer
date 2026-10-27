import Cocoa
import QuickLookUI
import WebKit

final class PreviewViewController: NSViewController, QLPreviewingController {
    private var preview: PreviewController!
    private var scopedURL: URL?
    private var completion: ((Error?) -> Void)?

    override func loadView() {
        preview = PreviewController()
        view = preview.webView
        preferredContentSize = NSSize(width: 900, height: 760)
        preview.onRendered = { [weak self] in
            self?.completion?(nil)
            self?.completion = nil
        }
        preview.onError = { [weak self] message in
            self?.completion?(NSError(domain: "ClearMark", code: 1, userInfo: [NSLocalizedDescriptionKey: message]))
            self?.completion = nil
        }
        preview.onLink = { href in
            guard let url = URL(string: href), ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") else { return }
            NSWorkspace.shared.open(url)
        }
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        _ = view
        completion?(CocoaError(.userCancelled))
        completion = nil
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = url.startAccessingSecurityScopedResource() ? url : nil
        do {
            let document = try DocumentContent.read(url)
            completion = handler
            preview.display(document)
        } catch { handler(error) }
    }

    deinit { scopedURL?.stopAccessingSecurityScopedResource() }
}
