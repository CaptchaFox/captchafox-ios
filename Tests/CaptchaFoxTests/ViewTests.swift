import Testing
import UIKit
import WebKit
@testable import CaptchaFox

@MainActor
struct ViewTests {
    init() async throws {
        try await WebKitWarmUp.ready()
    }

    @Test func showsAnIndicatorUntilTheWidgetIsLoaded() async throws {
        let harness = WidgetHarness()
        let view = CaptchaFoxUIView(bridge: harness.bridge)
        var loaded = false
        view.onLoad = { loaded = true }

        #expect(view.loadingIndicator.isAnimating)
        try await until { loaded }
        #expect(!view.loadingIndicator.isAnimating)
    }

    @Test func showsNoIndicatorWhenTurnedOff() {
        let view = CaptchaFoxUIView(bridge: WidgetHarness().bridge)
        view.showsLoadingIndicator = false

        #expect(!view.loadingIndicator.isAnimating)
    }

    @Test func stopsTheIndicatorWhenTheWidgetCannotLoad() async throws {
        let harness = WidgetHarness(scriptURL: URL(string: "unreachable://cdn.example/api.js")!)
        let view = CaptchaFoxUIView(bridge: harness.bridge)
        var failed = false
        view.onError = { _ in failed = true }

        try await until { failed }
        #expect(!view.loadingIndicator.isAnimating)
    }

    @Test func anOpenedChallengeShowsOverTheWholeWindow() async throws {
        let shown = try await ShownView()

        try await shown.openChallenge()

        let overlay = try #require(shown.view.overlay)
        #expect(shown.window.subviews.last === overlay)
        #expect(overlay.frame == shown.window.bounds)
        #expect(overlay.backgroundColor == CaptchaFoxModalViewController.defaultBackdropColor)
        #expect(overlay.accessibilityViewIsModal)
        #expect(shown.webView.superview === overlay)
        overlay.layoutIfNeeded()
        #expect(shown.webView.frame == overlay.bounds.inset(by: overlay.safeAreaInsets))

        shown.window.frame = CGRect(x: 0, y: 0, width: 844, height: 390)
        #expect(overlay.frame == shown.window.bounds)
    }

    @Test(arguments: [("onClose", []), ("onError", ["Something failed"]), ("onFail", []), ("onExpire", [])])
    func theWebViewReturnsBeforeTheCallbackOf(_ callback: String, _ arguments: [String]) async throws {
        let shown = try await ShownView()
        var returnedBeforeCallback: Bool?
        let record = { [weak shown] in
            returnedBeforeCallback = shown.map { $0.webView.superview === $0.view && $0.view.overlay == nil }
        }
        shown.view.onClose = record
        shown.view.onError = { _ in record() }
        shown.view.onFail = record
        shown.view.onExpire = record
        try await shown.openChallengeFullScreen()
        let overlay = try #require(shown.view.overlay)

        try await shown.harness.widgetCalls(callback, arguments)
        try await until { returnedBeforeCallback != nil }

        #expect(returnedBeforeCallback == true)
        #expect(overlay.superview == nil)
        #expect(shown.webView.frame == shown.view.bounds)
    }

    @Test func afterVerifyTheWebViewReturnsOnceTheWidgetShowedItsSuccessState() async throws {
        let shown = try await ShownView()
        var verifiedAt: Date?
        shown.view.onVerify = { _ in verifiedAt = Date() }
        try await shown.openChallengeFullScreen()

        try await shown.harness.widgetCalls("onVerify", ["token-1"])
        try await until { shown.webView.superview === shown.view }

        let verified = try #require(verifiedAt)
        #expect(Date().timeIntervalSince(verified) >= CaptchaFoxUIView.challengeEndDelayAfterVerify)
        #expect(shown.view.overlay == nil)
    }

    @Test func theAppCanPresentWhileTheChallengeShows() async throws {
        let shown = try await ShownView()
        let alert = UIViewController()
        var verified = false
        shown.view.onVerify = { [weak shown] _ in
            shown?.root.present(alert, animated: false)
            verified = true
        }
        try await shown.openChallengeFullScreen()

        // The overlay stays for a moment after verify.
        try await shown.harness.widgetCalls("onVerify", ["token-1"])
        try await until { verified }

        #expect(shown.view.overlay != nil)
        #expect(shown.root.presentedViewController === alert)
    }

    @Test func anEndedChallengeLeavesTheAppsWindowAsItWas() async throws {
        let shown = try await ShownView()
        let sheet = UIViewController()
        shown.root.present(sheet, animated: false)
        let windowViews = shown.window.subviews
        let rootViews = shown.root.view.subviews

        try await shown.openChallengeFullScreen()
        try await shown.harness.widgetCalls("onClose")
        try await until { shown.webView.superview === shown.view }

        #expect(shown.window.subviews.elementsEqual(windowViews, by: ===))
        #expect(shown.root.view.subviews.elementsEqual(rootViews, by: ===))
        #expect(shown.root.presentedViewController === sheet)
    }

    @Test func aChallengeThatOpensBeforeTheDelayAfterVerifyStaysOverTheWindow() async throws {
        let shown = try await ShownView()
        var verifiedAt: Date?
        shown.view.onVerify = { _ in verifiedAt = Date() }
        try await shown.openChallengeFullScreen()
        let overlay = shown.view.overlay

        try await shown.harness.widgetCalls("onVerify", ["token-1"])
        try await shown.openChallenge()
        let verified = try #require(verifiedAt)
        // Twice the delay, so that a return it had not cancelled would have happened.
        try await until { Date().timeIntervalSince(verified) > 2 * CaptchaFoxUIView.challengeEndDelayAfterVerify }

        #expect(shown.view.overlay === overlay)
        #expect(shown.webView.superview === overlay)
    }

    @Test func resetReturnsTheWebView() async throws {
        let shown = try await ShownView()
        try await shown.openChallengeFullScreen()

        shown.view.reset()

        #expect(shown.webView.superview === shown.view)
        #expect(shown.view.overlay == nil)
    }

    @Test func theEndOfTheWebViewsProcessReturnsTheWebView() async throws {
        let shown = try await ShownView()
        try await shown.openChallengeFullScreen()

        // As WebKit reports it; ExecuteTests ends the process itself, which WebKit does not always do in the test process.
        shown.harness.bridge.webViewWebContentProcessDidTerminate(shown.webView)

        #expect(shown.webView.superview === shown.view)
        #expect(shown.view.overlay == nil)
    }

    @Test func leavingTheWindowReturnsTheWebViewAndComingBackShowsTheOpenChallengeAgain() async throws {
        let shown = try await ShownView()
        try await shown.openChallengeFullScreen()
        let overlay = try #require(shown.view.overlay)

        shown.view.removeFromSuperview()
        #expect(shown.webView.superview === shown.view)
        #expect(overlay.superview == nil)

        shown.root.view.addSubview(shown.view)
        #expect(shown.view.overlay?.superview === shown.window)
        #expect(shown.webView.superview === shown.view.overlay)
    }

    @Test func aChallengeThatOpensAgainShowsOverTheWindowAgain() async throws {
        let shown = try await ShownView()
        try await shown.openChallengeFullScreen()
        try await shown.harness.widgetCalls("onClose")
        try await until { shown.webView.superview === shown.view }

        try await shown.openChallenge()

        #expect(shown.view.overlay?.superview === shown.window)
        #expect(shown.webView.superview === shown.view.overlay)
    }
}

/// A loaded view at the size of the widget's box on the screen of a window's root controller.
@MainActor
private final class ShownView {
    let harness = WidgetHarness()
    let view: CaptchaFoxUIView
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    let root = UIViewController()
    private var challengesOpened = 0

    init() async throws {
        view = CaptchaFoxUIView(bridge: harness.bridge)
        view.frame = CGRect(x: 20, y: 100, width: 300, height: 80)
        window.rootViewController = root
        window.makeKeyAndVisible()
        root.view.addSubview(view)
        try #require(view.window === window)
        var loaded = false
        view.onLoad = { loaded = true }
        view.onChallengeOpen = { [weak self] in self?.challengesOpened += 1 }
        try await until { loaded }
    }

    var webView: WKWebView {
        harness.bridge.webView
    }

    /// Opens a challenge as the widget does and returns once the view has called `onChallengeOpen`.
    func openChallenge() async throws {
        let opened = challengesOpened
        try await harness.widgetCalls("onChallengeOpen")
        try await until { challengesOpened == opened + 1 }
    }

    /// Opens a challenge and requires that the web view is in the overlay.
    func openChallengeFullScreen() async throws {
        try await openChallenge()
        try #require(webView.superview === view.overlay && view.overlay != nil)
    }
}
