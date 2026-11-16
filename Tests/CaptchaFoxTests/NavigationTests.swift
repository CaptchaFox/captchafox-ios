import Foundation
import Testing
import WebKit
@testable import CaptchaFox

@MainActor
struct NavigationTests {
    @Test func theMainFrameDoesNotLeaveThePage() async throws {
        let away = RecordingSchemeHandler()
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(away, forURLScheme: "away")
        let harness = try await WidgetHarness.loaded(webViewConfiguration: configuration)

        try await harness.page("window.location.href = 'away://example/'")
        // A navigation that is not cancelled reaches the scheme handler within milliseconds.
        try await Task.sleep(nanoseconds: 2_000_000_000)

        #expect(away.requests.isEmpty)
        #expect(try await harness.page("return document.getElementById('captchafox') !== null") as? Bool == true)
    }

    @Test func aTappedLinkOpensInTheSystemBrowser() async throws {
        let harness = try await WidgetHarness.loaded()

        try await harness.page("""
            var link = document.createElement('a');
            link.href = 'https://captchafox.com/privacy';
            document.body.appendChild(link);
            link.click();
            """)
        try await until { harness.opened.count == 1 }

        #expect(harness.opened == [URL(string: "https://captchafox.com/privacy")!])
        #expect(try await harness.page("return document.getElementById('captchafox') !== null") as? Bool == true)
    }

    @Test(arguments: [
        PolicyCase(targetIsMainFrame: false, url: "https://captchafox.com/frame", isLinkActivated: false, policy: .allow, opens: false),
        PolicyCase(targetIsMainFrame: true, url: "https://app.example/", isLinkActivated: false, policy: .cancel, opens: false),
        PolicyCase(targetIsMainFrame: true, url: "https://elsewhere.example/", isLinkActivated: false, policy: .cancel, opens: false),
        PolicyCase(targetIsMainFrame: true, url: "https://captchafox.com/privacy", isLinkActivated: true, policy: .cancel, opens: true),
        PolicyCase(targetIsMainFrame: nil, url: "https://captchafox.com/terms", isLinkActivated: true, policy: .cancel, opens: true),
        PolicyCase(targetIsMainFrame: nil, url: "https://elsewhere.example/", isLinkActivated: false, policy: .cancel, opens: false),
        PolicyCase(targetIsMainFrame: true, url: "tel:123", isLinkActivated: true, policy: .cancel, opens: false),
        PolicyCase(targetIsMainFrame: nil, url: "javascript:alert(1)", isLinkActivated: true, policy: .cancel, opens: false),
    ])
    func policyOnceThePageIsLoaded(_ testCase: PolicyCase) async throws {
        let harness = try await WidgetHarness.loaded()
        let url = try #require(URL(string: testCase.url))

        let policy = harness.bridge.policy(targetIsMainFrame: testCase.targetIsMainFrame, url: url, isLinkActivated: testCase.isLinkActivated)

        #expect(policy == testCase.policy)
        #expect(harness.opened == (testCase.opens ? [url] : []))
    }
}

struct PolicyCase: Sendable, CustomTestStringConvertible {
    let targetIsMainFrame: Bool?
    let url: String
    let isLinkActivated: Bool
    let policy: WKNavigationActionPolicy
    let opens: Bool

    var testDescription: String {
        "\(targetIsMainFrame.map { $0 ? "main frame" : "frame" } ?? "new window"), \(url), \(isLinkActivated ? "link" : "script")"
    }
}

@MainActor
final class RecordingSchemeHandler: NSObject, WKURLSchemeHandler {
    private(set) var requests: [URLRequest] = []

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        requests.append(urlSchemeTask.request)
        urlSchemeTask.didFailWithError(URLError(.cancelled))
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}
}
