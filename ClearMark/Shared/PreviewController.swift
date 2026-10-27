import AppKit
import WebKit

@MainActor
final class PreviewController: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    let webView: WKWebView
    let resourceHandler = ResourceSchemeHandler()
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

    func display(_ document: DocumentContent, settings: PreviewSettings = PreviewSettings()) {
        revision += 1
        source = document.text
        options = settings.javascriptOptions
        options["title"] = document.title
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
            case .failure(let error): self.onError?(L10n.text("The preview could not render.") + " " + error.localizedDescription)
            }
        }
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
        if action == "link", let href = body["href"] as? String { onLink?(href) }
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
