import AppKit
import WebKit

struct OutlineItem: Identifiable, Equatable {
    let id: String
    let title: String
    let level: Int
}

@MainActor
final class PreviewController: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    let webView: WKWebView
    let resourceHandler = ResourceSchemeHandler()
    var onOutline: (([OutlineItem]) -> Void)?
    var onLink: ((String) -> Void)?
    var onError: ((String) -> Void)?
    var onRendered: (() -> Void)?
    private var ready = false
    private var revision = 0
    private var source = ""
    private var options: [String: Any] = [:]

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(resourceHandler, forURLScheme: "clearmark")
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        // A weak proxy avoids a retain cycle through WKUserContentController.
        configuration.userContentController.add(WeakMessageHandler(self), name: "clearmark")
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = true
        webView.load(URLRequest(url: URL(string: "clearmark://bundle/preview.html")!))
    }

    func display(_ document: DocumentContent, theme: String = "system", fontSize: Double = 17, wide: Bool = false) {
        revision += 1
        source = document.text
        options = ["theme": theme, "fontSize": fontSize, "wide": wide, "title": document.title]
        resourceHandler.documentDirectory = document.url?.deletingLastPathComponent() ?? PreviewResources.root
        resourceHandler.resetBudget()
        render()
    }

    private func render() {
        guard ready else { return }
        let currentRevision = revision
        webView.callAsyncJavaScript("await window.ClearMark.render(markdown, options); return true", arguments: ["markdown": source, "options": options], in: nil, in: .page) { [weak self] result in
            guard let self, self.revision == currentRevision else { return }
            switch result {
            case .success: self.onRendered?()
            case .failure(let error): self.onError?("The preview could not render: \(error.localizedDescription)")
            }
        }
    }

    func scroll(to id: String) {
        webView.callAsyncJavaScript("document.getElementById(id)?.scrollIntoView({behavior: 'smooth', block: 'start'})", arguments: ["id": id], in: nil, in: .page, completionHandler: nil)
    }

    func find(_ query: String, backwards: Bool = false) {
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.wraps = true
        webView.find(query, configuration: configuration) { _ in }
    }

    func pdfData() async throws -> Data {
        let dimensions = try await webView.evaluateJavaScript("({width: document.documentElement.clientWidth, height: document.documentElement.scrollHeight})") as? [String: Double]
        guard let width = dimensions?["width"], let height = dimensions?["height"], width > 0, height > 0 else { throw CocoaError(.fileWriteUnknown) }
        let configuration = WKPDFConfiguration()
        configuration.rect = CGRect(x: 0, y: 0, width: width, height: height)
        return try await webView.pdf(configuration: configuration)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { ready = true; render() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { onError?(error.localizedDescription) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { onError?(error.localizedDescription) }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.navigationType == .linkActivated {
            if let url = navigationAction.request.url { onLink?(url.absoluteString) }
            decisionHandler(.cancel)
        } else {
            decisionHandler(navigationAction.request.url?.absoluteString == "clearmark://bundle/preview.html" ? .allow : .cancel)
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
        if action == "outline", let entries = body["items"] as? [[String: Any]] {
            onOutline?(entries.compactMap { item in
                guard let id = item["id"] as? String, let title = item["title"] as? String, let level = item["level"] as? Int else { return nil }
                return OutlineItem(id: id, title: title, level: level)
            })
        } else if action == "link", let href = body["href"] as? String { onLink?(href) }
        else if action == "copy", let text = body["text"] as? String {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }
}

private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
