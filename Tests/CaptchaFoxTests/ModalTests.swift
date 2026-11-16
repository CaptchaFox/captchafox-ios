import Testing
import UIKit
@testable import CaptchaFox

@MainActor
struct ModalTests {
    @Test func showsTheWidgetOnceItIsLoaded() async throws {
        let (modal, harness) = makeModal(mode: nil)
        var loaded = false
        modal.onLoad = { loaded = true }

        #expect(modal.widget?.alpha == 0)
        #expect(modal.loadingIndicator.isAnimating)
        try await until { loaded }

        #expect(modal.widget?.alpha == 1)
        #expect(!modal.loadingIndicator.isAnimating)
        #expect(try await harness.executionCount() == 0)
    }

    @Test func inHiddenModeExecutesOnLoadAndShowsTheWidgetOnlyForAChallenge() async throws {
        let (modal, harness) = makeModal(mode: .hidden)
        var challengeOpened = false
        modal.onChallengeOpen = { challengeOpened = true }

        try await until { try await harness.page("return window.fake && window.fake.executions") as? Int == 1 }
        #expect(modal.widget?.alpha == 0)
        #expect(modal.loadingIndicator.isAnimating)

        try await harness.widgetCalls("onChallengeOpen")
        try await until { challengeOpened }
        #expect(modal.widget?.alpha == 1)
        // The indicator stays below the web view, for the time between the challenge and the token.
        #expect(modal.loadingIndicator.isAnimating)
        let widget = try #require(modal.widget)
        let indicatorIndex = try #require(modal.view.subviews.firstIndex(of: modal.loadingIndicator))
        let widgetIndex = try #require(modal.view.subviews.firstIndex(of: widget))
        #expect(indicatorIndex < widgetIndex)
    }

    @Test(arguments: [("onVerify", ["token-1"]), ("onError", ["Something failed"]), ("onClose", [])])
    func finishesOn(_ callback: String, _ arguments: [String]) async throws {
        let (modal, harness) = makeModal(mode: nil)
        var calls: [String] = []
        modal.onLoad = { calls.append("onLoad") }
        modal.onFail = { calls.append("onFail") }
        modal.onExpire = { calls.append("onExpire") }
        modal.onVerify = { _ in calls.append("onVerify") }
        modal.onError = { _ in calls.append("onError") }
        modal.onClose = { calls.append("onClose") }
        modal.onFinish = { calls.append("finish") }
        try await until { calls == ["onLoad"] }

        try await harness.widgetCalls("onFail")
        try await harness.widgetCalls("onExpire")
        try await harness.widgetCalls(callback, arguments)
        try await harness.widgetCalls(callback, arguments)
        try await until { calls.count == 6 }

        #expect(calls == ["onLoad", "onFail", "onExpire", callback, "finish", callback])
    }

    @Test func inHiddenModeAFailedExecutionFinishesTheModal() async throws {
        let (modal, harness) = makeModal(mode: .hidden)
        var calls: [String] = []
        modal.onError = { calls.append("onError \($0)") }
        modal.onFinish = { calls.append("finish") }
        try await until { try await harness.page("return window.fake && window.fake.executions") as? Int == 1 }

        try await harness.page("window.fake.rejectExecution(new Error('challenge-aborted'))")
        try await until { calls.count == 2 }

        #expect(calls == ["onError challenge-aborted", "finish"])
    }

    @Test func inHiddenModeAnErrorIsReportedOnce() async throws {
        let (modal, harness) = makeModal(mode: .hidden)
        var calls: [String] = []
        modal.onError = { calls.append("onError \($0)") }
        modal.onFail = { calls.append("onFail") }
        modal.onFinish = { calls.append("finish") }
        try await until { try await harness.page("return window.fake && window.fake.executions") as? Int == 1 }

        try await harness.widgetCalls("onError", ["challenge-failed"])
        try await harness.page("window.fake.rejectExecution(new Error('challenge-failed'))")
        try await harness.widgetCalls("onFail")
        try await until { calls.last == "onFail" }

        #expect(calls == ["onError challenge-failed", "finish", "onFail"])
    }

    @Test func createsTheWidgetOnlyWhenItsViewLoads() {
        var made = 0
        let modal = CaptchaFoxModalViewController(mode: .hidden) {
            made += 1
            return CaptchaFoxUIView(bridge: WidgetHarness().bridge)
        }

        #expect(made == 0)
        modal.loadViewIfNeeded()
        #expect(made == 1)
    }

    @Test func placesTheHeaderAboveAndTheFooterBelowTheWidgetOnItsBackdrop() throws {
        let header = UILabel()
        header.text = "Header"
        let footer = UILabel()
        footer.text = "Footer"
        let (modal, _) = makeModal(mode: nil) { modal in
            modal.backdropColor = .red
            modal.headerView = header
            modal.footerView = footer
        }
        modal.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        modal.view.layoutIfNeeded()

        let widget = try #require(modal.widget)
        #expect(modal.view.backgroundColor == .red)
        #expect(header.frame.height > 0 && footer.frame.height > 0)
        // Within half a point: Auto Layout rounds to pixels.
        #expect(abs(header.frame.maxY - widget.frame.minY) < 0.5)
        #expect(abs(footer.frame.minY - widget.frame.maxY) < 0.5)
        #expect(widget.frame.height > 0)
    }

    @Test func aLoadingViewTakesTheIndicatorsPlaceBelowTheWidget() async throws {
        let loadingView = UILabel()
        var loaded = false
        let (modal, _) = makeModal(mode: nil) { modal in
            modal.loadingView = loadingView
            modal.onLoad = { loaded = true }
        }

        let widget = try #require(modal.widget)
        #expect(modal.loadingIndicator.superview == nil)
        let loadingIndex = try #require(modal.view.subviews.firstIndex(of: loadingView))
        let widgetIndex = try #require(modal.view.subviews.firstIndex(of: widget))
        #expect(loadingIndex < widgetIndex)
        #expect(!loadingView.isHidden)

        try await until { loaded }
        #expect(loadingView.isHidden)
    }

    @Test func dismissesTheDelayAfterVerify() async throws {
        var verifiedAt: Date?
        var finishedAt: Date?
        let (modal, harness) = makeModal(mode: nil) { modal in
            modal.dismissDelayAfterVerify = 0.3
            modal.onVerify = { _ in verifiedAt = Date() }
            modal.onFinish = { finishedAt = Date() }
        }
        try await until { modal.widget?.alpha == 1 }

        try await harness.widgetCalls("onVerify", ["token-1"])
        try await until { finishedAt != nil }

        let verified = try #require(verifiedAt)
        let finished = try #require(finishedAt)
        #expect(finished.timeIntervalSince(verified) >= 0.3)
        withExtendedLifetime(modal) {}
    }

    @Test func aCloseDuringTheDelayIsPassedOnButFinishesNothing() async throws {
        var calls: [String] = []
        let (modal, harness) = makeModal(mode: nil) { modal in
            // Longer than the test runs, so that only a close could finish the modal.
            modal.dismissDelayAfterVerify = 3600
            modal.onVerify = { _ in calls.append("onVerify") }
            modal.onClose = { calls.append("onClose") }
            modal.onFinish = { calls.append("finish") }
        }
        try await until { modal.widget?.alpha == 1 }

        try await harness.widgetCalls("onVerify", ["token-1"])
        try await harness.widgetCalls("onClose")
        try await until { calls.contains("onClose") }

        #expect(calls == ["onVerify", "onClose"])
        withExtendedLifetime(modal) {}
    }

    @Test func aChallengeStaysInTheModal() async throws {
        let (modal, harness) = makeModal(mode: nil)
        let widget = try #require(modal.widget)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.addSubview(modal.view)
        var challengeOpened = false
        modal.onChallengeOpen = { challengeOpened = true }
        try await until { widget.alpha == 1 }

        try await harness.widgetCalls("onChallengeOpen")
        try await until { challengeOpened }

        #expect(window.subviews.elementsEqual([modal.view], by: ===))
        #expect(harness.bridge.webView.superview === widget)
    }

    @Test func theWidgetShowsNoIndicatorOfItsOwn() throws {
        let (modal, _) = makeModal(mode: nil)

        #expect(try #require(modal.widget).showsLoadingIndicator == false)
    }

    /// A modal whose widget runs on the harness's page; the harness's own events stop, the modal's callbacks report them.
    private func makeModal(
        mode: CaptchaFoxConfiguration.Mode?,
        before load: (CaptchaFoxModalViewController) -> Void = { _ in }
    ) -> (CaptchaFoxModalViewController, WidgetHarness) {
        let harness = WidgetHarness(configuration: WidgetHarness.configuration(mode: mode))
        let modal = CaptchaFoxModalViewController(mode: mode) {
            CaptchaFoxUIView(bridge: harness.bridge)
        }
        modal.dismissDelayAfterVerify = 0
        load(modal)
        modal.loadViewIfNeeded()
        return (modal, harness)
    }
}
