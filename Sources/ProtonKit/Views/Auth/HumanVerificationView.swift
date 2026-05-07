import SwiftUI
import WebKit
import ProtonCore

struct HumanVerificationView: NSViewRepresentable {
    let captchaURL: URL
    let onToken: (String) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()

        contentController.add(context.coordinator, name: "linuxWebkitWebview")

        let script = WKUserScript(source: """
            window.addEventListener('message', function(event) {
                try {
                    var data = event.data;
                    if (typeof data === 'object') {
                        if (data.type === 'pm_captcha' || data.type === 'HUMAN_VERIFICATION_SUCCESS') {
                            window.webkit.messageHandlers.linuxWebkitWebview.postMessage(JSON.stringify(data));
                        }
                    }
                } catch(e) {}
            });
        """, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        contentController.addUserScript(script)

        config.userContentController = contentController
        config.preferences.setValue(true, forKey: "javaScriptCanOpenWindowsAutomatically")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        webView.load(URLRequest(url: captchaURL))
        ProtonClient.debugLog("HV WebView loading: \(captchaURL.absoluteString)")
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onToken: onToken)
    }

    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let onToken: (String) -> Void

        init(onToken: @escaping (String) -> Void) {
            self.onToken = onToken
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            ProtonClient.debugLog("HV message: \(message.body)")
            if let dict = message.body as? [String: Any],
               let token = dict["token"] as? String {
                onToken(token)
                return
            }
            if let body = message.body as? String {
                if let data = body.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let token = json["token"] as? String {
                    onToken(token)
                    return
                }
                if body.contains(":") && body.count > 10 {
                    onToken(body)
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            ProtonClient.debugLog("HV page loaded: \(webView.url?.absoluteString ?? "nil")")
            webView.evaluateJavaScript("document.body.innerText") { result, _ in
                if let text = result as? String, !text.isEmpty {
                    ProtonClient.debugLog("HV page text: \(String(text.prefix(200)))")
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            ProtonClient.debugLog("HV navigation failed: \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            ProtonClient.debugLog("HV provisional navigation failed: \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url {
                ProtonClient.debugLog("HV navigating to: \(url.absoluteString)")
            }
            decisionHandler(.allow)
        }
    }
}
