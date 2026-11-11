import Foundation
import Testing
import WebKit
@testable import CaptchaFox

/// A bridge whose page loads a fake of the widget's script instead of cdn.captchafox.com, so that tests drive the
/// widget's callbacks and need no network.
@MainActor
final class WidgetHarness {
    static let baseURL = URL(string: "https://app.example/")!

    let bridge: WidgetBridge
    private(set) var events: [WidgetEvent] = []
    private let openedURLs: OpenedURLs

    init(
        configuration: CaptchaFoxConfiguration = WidgetHarness.configuration(),
        webViewConfiguration: WKWebViewConfiguration = WKWebViewConfiguration(),
        scriptURL: URL = WidgetHarness.fakeScriptURL
    ) {
        let openedURLs = OpenedURLs()
        self.openedURLs = openedURLs
        bridge = WidgetBridge(
            configuration: configuration,
            scriptURL: scriptURL,
            webViewConfiguration: webViewConfiguration,
            openURL: { openedURLs.urls.append($0) }
        )
        bridge.onEvent = { [weak self] event in
            self?.events.append(event)
        }
        keepAwake(bridge.webView)
    }

    /// The URLs the bridge opened in the system browser.
    var opened: [URL] {
        openedURLs.urls
    }

    static func configuration(siteKey: String = "sk_test", mode: CaptchaFoxConfiguration.Mode? = nil) -> CaptchaFoxConfiguration {
        CaptchaFoxConfiguration(siteKey: siteKey, baseURL: baseURL, mode: mode)
    }

    /// A harness whose widget has reported that it is loaded.
    static func loaded(configuration: CaptchaFoxConfiguration = WidgetHarness.configuration(), webViewConfiguration: WKWebViewConfiguration = WKWebViewConfiguration()) async throws -> WidgetHarness {
        let harness = WidgetHarness(configuration: configuration, webViewConfiguration: webViewConfiguration)
        try await until { harness.events == [.load] }
        return harness
    }

    /// Calls `execute()` and returns once the page has called the widget's `execute`.
    func startExecution() async throws -> Execution {
        let executions = try await executionCount()
        let execution = Execution(bridge)
        try await until { try await self.executionCount() == executions + 1 }
        return execution
    }

    func executionCount() async throws -> Int {
        try await page("return window.fake.executions") as? Int ?? -1
    }

    /// Calls the callback that the page passed to the fake widget's `render`, as the widget does.
    func widgetCalls(_ callback: String, _ arguments: [Any] = []) async throws {
        try await page("window.fake.options[callback].apply(null, args)", ["callback": callback, "args": arguments])
    }

    /// Posts a message to the bridge from the page's main frame.
    func post(_ message: Any) async throws {
        try await page("window.webkit.messageHandlers.captchafox.postMessage(message)", ["message": message])
    }

    /// Runs JavaScript in the page as the body of an async function with the given arguments.
    @discardableResult
    func page(_ body: String, _ arguments: [String: Any] = [:]) async throws -> Any? {
        try await bridge.webView.callAsyncJavaScript(body, arguments: arguments, contentWorld: .page)
    }

    private static let fakeScript = """
        window.fake = { executions: 0, resets: 0, rejections: [] };
        window.captchafox = {
          render: function (element, options) {
            window.fake.element = element;
            window.fake.options = options;
            return 'widget';
          },
          execute: function () {
            window.fake.executions += 1;
            return new Promise(function (resolve, reject) {
              window.fake.rejections.push(reject);
              window.fake.rejectExecution = reject;
            });
          },
          reset: function () { window.fake.resets += 1; },
        };
        window.captchafoxOnLoad();
        """

    static let fakeScriptURL = URL(string: "data:text/javascript;base64," + Data(fakeScript.utf8).base64EncodedString())!
}

/// A call of `execute()` in a task of its own, whose outcome tests wait for with a timeout instead of hanging.
@MainActor
final class Execution {
    private(set) var result: Result<String, any Error>?
    private var task: Task<Void, Never>?

    init(_ bridge: WidgetBridge) {
        task = Task {
            do {
                result = .success(try await bridge.execute())
            } catch {
                result = .failure(error)
            }
        }
    }

    func cancel() {
        task?.cancel()
    }

    /// The token, or the error the call threw.
    func token() async throws -> String {
        try await until { result != nil }
        return try result!.get()
    }
}

/// The test process is no foreground app, so WebKit freezes a web view's process after some seconds; on the first boot
/// of a simulator, the page is not loaded by then. A call into the page every 200 ms keeps the process awake, as an app
/// in the foreground does.
@MainActor
func keepAwake(_ webView: WKWebView) {
    Task { [weak webView] in
        while let webView {
            _ = try? await webView.evaluateJavaScript("0")
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }
}

/// Waits until the condition holds. On the first boot of a new simulator device, WebKit's processes take more than a
/// minute to launch.
@MainActor
func until(timeout: TimeInterval = 180, _ condition: () async throws -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while try await !condition() {
        guard Date() < deadline else {
            throw WaitTimeout()
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
}

struct WaitTimeout: Error {}

@MainActor
private final class OpenedURLs {
    var urls: [URL] = []
}
