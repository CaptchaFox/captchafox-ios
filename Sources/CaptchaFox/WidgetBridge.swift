import UIKit
import WebKit

/// Owns the web view with the widget's page: loads the page, turns its messages into events, settles `execute()` and
/// keeps the web view on the page.
@MainActor
final class WidgetBridge: NSObject {
    let webView: WKWebView
    var onEvent: (WidgetEvent) -> Void = { _ in }
    /// Called when the web view's process ended; the page loads again, without an open challenge.
    var onWebContentTerminated: () -> Void = {}

    private let page: String
    private let baseURL: URL
    private let openURL: (URL) -> Void
    private var expectsPageLoad = false
    private var isLoaded = false
    private var pending: PendingExecution?
    private var executionCount = 0

    private struct PendingExecution {
        let id: Int
        let continuation: CheckedContinuation<String, any Error>
    }

    init(
        configuration: CaptchaFoxConfiguration,
        scriptURL: URL = WidgetPage.scriptURL,
        webViewConfiguration: WKWebViewConfiguration = WKWebViewConfiguration(),
        openURL: @escaping (URL) -> Void = { UIApplication.shared.open($0) }
    ) {
        let messageHandler = MessageHandler()
        webViewConfiguration.userContentController.add(messageHandler, name: WidgetPage.messageHandlerName)
        webView = WKWebView(frame: .zero, configuration: webViewConfiguration)
        page = WidgetPage.html(configuration: configuration, scriptURL: scriptURL)
        baseURL = configuration.baseURL
        self.openURL = openURL
        super.init()

        messageHandler.bridge = self
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear

        loadPage()
    }

    func execute() async throws -> String {
        try Task.checkCancellation()
        guard isLoaded else {
            throw CaptchaFoxError(.notLoaded)
        }

        settle(.failure(CaptchaFoxError(.superseded)))
        executionCount += 1
        let id = executionCount
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending = PendingExecution(id: id, continuation: continuation)
                webView.callAsyncJavaScript("window.captchafoxExecute(id)", arguments: ["id": id], in: nil, in: .page)
            }
        } onCancel: {
            Task { @MainActor in
                self.cancel(executionID: id)
            }
        }
    }

    func reset() {
        settle(.failure(CaptchaFoxError(.reset)))
        guard isLoaded else {
            return
        }

        webView.evaluateJavaScript("window.captchafoxReset()", completionHandler: nil)
    }

    func receive(_ body: Any, isMainFrame: Bool) {
        // Only the widget's page runs in the main frame; a frame inside it never speaks for the widget.
        guard isMainFrame, let message = PageMessage(body: body) else {
            return
        }

        switch message {
        case .event(let event):
            deliver(event)
        case .executionFailed(let id, let reason):
            // A late failure of an earlier call must not settle the call that superseded it.
            guard pending?.id == id else {
                return
            }
            settle(.failure(CaptchaFoxError(.widget, message: reason)))
        }
    }

    /// The main frame shows only the widget's page: the one load of it is allowed, every other navigation of the main
    /// frame or into a new window is cancelled, and a link the visitor tapped opens in the system browser.
    func policy(targetIsMainFrame: Bool?, url: URL?, isLinkActivated: Bool) -> WKNavigationActionPolicy {
        switch targetIsMainFrame {
        case false?:
            // Frames inside the page, such as the widget's.
            return .allow
        case true?:
            if expectsPageLoad {
                expectsPageLoad = false
                return .allow
            }
        case nil:
            // A new window, such as a link with target=_blank.
            break
        }

        if isLinkActivated, let url, ["http", "https"].contains(url.scheme?.lowercased()) {
            openURL(url)
        }
        return .cancel
    }

    private func loadPage() {
        expectsPageLoad = true
        webView.loadHTMLString(page, baseURL: baseURL)
    }

    private func deliver(_ event: WidgetEvent) {
        switch event {
        case .load:
            isLoaded = true
        case .verify(let token):
            settle(.success(token))
        case .error(let message):
            settle(.failure(CaptchaFoxError(.widget, message: message)))
        case .close:
            settle(.failure(CaptchaFoxError(.closed)))
        case .fail, .expire, .challengeOpen:
            break
        }
        onEvent(event)
    }

    private func settle(_ result: Result<String, any Error>) {
        guard let pending else {
            return
        }

        self.pending = nil
        pending.continuation.resume(with: result)
    }

    private func cancel(executionID: Int) {
        guard pending?.id == executionID else {
            return
        }

        settle(.failure(CancellationError()))
    }
}

extension WidgetBridge: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        decisionHandler(policy(
            targetIsMainFrame: navigationAction.targetFrame?.isMainFrame,
            url: navigationAction.request.url,
            isLinkActivated: navigationAction.navigationType == .linkActivated
        ))
    }

    /// iOS may end the web view's process, as under memory pressure; the page is gone then and loads again.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        isLoaded = false
        settle(.failure(CaptchaFoxError(.webContentTerminated)))
        onWebContentTerminated()
        loadPage()
    }
}

/// Holds the bridge weakly, because the web view's configuration retains its message handlers.
@MainActor
private final class MessageHandler: NSObject, WKScriptMessageHandler {
    weak var bridge: WidgetBridge?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        bridge?.receive(message.body, isMainFrame: message.frameInfo.isMainFrame)
    }
}
