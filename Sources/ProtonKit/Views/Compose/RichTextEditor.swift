import SwiftUI
import WebKit

@MainActor class RichTextActions: ObservableObject {
    weak var webView: WKWebView?

    func bold() { exec("bold") }
    func italic() { exec("italic") }
    func underline() { exec("underline") }
    func orderedList() { exec("insertOrderedList") }
    func unorderedList() { exec("insertUnorderedList") }

    private func exec(_ command: String) {
        webView?.evaluateJavaScript("document.execCommand('\(command)',false,null)")
    }
}

struct RichTextEditor: NSViewRepresentable {
    @Binding var html: String
    let actions: RichTextActions

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "contentChanged")

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        context.coordinator.webView = wv
        actions.webView = wv

        let page = """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <style>
        html, body { height: 100%; margin: 0; }
        body {
            font-family: -apple-system, system-ui, sans-serif;
            font-size: 14px; line-height: 1.6;
            padding: 12px; outline: none;
            color: #333; background: #fff;
        }
        blockquote { border-left: 2px solid #ccc; padding-left: 10px; margin-left: 0; color: #666; }
        </style></head>
        <body contenteditable="true" spellcheck="true"></body>
        <script>
        document.body.addEventListener('input', function() {
            window.webkit.messageHandlers.contentChanged.postMessage(document.body.innerHTML);
        });
        </script></html>
        """
        wv.loadHTMLString(page, baseURL: nil)
        return wv
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let parent: RichTextEditor
        weak var webView: WKWebView?
        private var didLoad = false

        init(_ parent: RichTextEditor) { self.parent = parent }

        func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "contentChanged", let html = message.body as? String {
                Task { @MainActor in self.parent.html = html }
            }
        }

        func webView(_ wv: WKWebView, didFinish navigation: WKNavigation!) {
            guard !didLoad else { return }
            didLoad = true
            let content = parent.html
            if !content.isEmpty {
                let b64 = Data(content.utf8).base64EncodedString()
                wv.evaluateJavaScript("""
                    document.body.innerHTML = atob('\(b64)');
                    var r = document.createRange(); r.setStart(document.body, 0); r.collapse(true);
                    var s = window.getSelection(); s.removeAllRanges(); s.addRange(r);
                    document.body.focus();
                """)
            } else {
                wv.evaluateJavaScript("document.body.focus()")
            }
        }

        func webView(_ wv: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated {
                if let url = navigationAction.request.url { NSWorkspace.shared.open(url) }
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
