import Foundation
import Testing
@testable import CaptchaFox

@MainActor
struct ExecuteTests {
    init() async throws {
        try await WebKitWarmUp.ready()
    }

    @Test func returnsTheTokenOnVerify() async throws {
        let harness = try await WidgetHarness.loaded()
        let execution = try await harness.startExecution()

        try await harness.widgetCalls("onVerify", ["token-1"])

        #expect(try await execution.token() == "token-1")
    }

    @Test func throwsTheWidgetsErrorOnError() async throws {
        let harness = try await WidgetHarness.loaded()
        let execution = try await harness.startExecution()

        try await harness.widgetCalls("onError", ["Something failed"])

        await #expect(throws: CaptchaFoxError(.widget, message: "Something failed")) { try await execution.token() }
    }

    @Test func throwsWhenTheWidgetRejectsTheExecution() async throws {
        let harness = try await WidgetHarness.loaded()
        let execution = try await harness.startExecution()

        try await harness.page("window.fake.rejectExecution(new Error('Rejected'))")

        await #expect(throws: CaptchaFoxError(.widget, message: "Rejected")) { try await execution.token() }
        // The widget reports the failure with its error callback as well; the rejection is no second event.
        #expect(harness.events == [.load])
    }

    @Test func throwsClosedOnClose() async throws {
        let harness = try await WidgetHarness.loaded()
        let execution = try await harness.startExecution()

        try await harness.widgetCalls("onClose")

        await #expect(throws: CaptchaFoxError(.closed)) { try await execution.token() }
    }

    @Test func otherEventsLeaveItPending() async throws {
        let harness = try await WidgetHarness.loaded()
        let execution = try await harness.startExecution()

        try await harness.widgetCalls("onChallengeOpen")
        try await harness.widgetCalls("onFail")
        try await harness.widgetCalls("onExpire")
        try await until { harness.events.last == .expire }
        #expect(execution.result == nil)
        try await harness.widgetCalls("onVerify", ["token-1"])

        #expect(try await execution.token() == "token-1")
        #expect(harness.events == [.load, .challengeOpen, .fail, .expire, .verify(token: "token-1")])
    }

    @Test func aSecondCallSettlesThePendingOne() async throws {
        let harness = try await WidgetHarness.loaded()
        let first = try await harness.startExecution()
        let second = try await harness.startExecution()

        await #expect(throws: CaptchaFoxError(.superseded)) { try await first.token() }
        try await harness.widgetCalls("onVerify", ["token-2"])
        #expect(try await second.token() == "token-2")
    }

    @Test func aLateFailureOfAnEarlierCallLeavesTheNewOnePending() async throws {
        let harness = try await WidgetHarness.loaded()
        let first = try await harness.startExecution()
        let second = try await harness.startExecution()
        await #expect(throws: CaptchaFoxError(.superseded)) { try await first.token() }

        try await harness.page("window.fake.rejections[0](new Error('Late'))")
        try await harness.widgetCalls("onFail")
        try await until { harness.events.last == .fail }

        #expect(second.result == nil)
        try await harness.widgetCalls("onVerify", ["token-2"])
        #expect(try await second.token() == "token-2")
    }

    @Test func cancellingTheCallingTaskSettlesIt() async throws {
        let harness = try await WidgetHarness.loaded()
        let execution = try await harness.startExecution()

        execution.cancel()

        await #expect(throws: CancellationError.self) { try await execution.token() }
        try await harness.widgetCalls("onVerify", ["late"])
        try await until { harness.events.last == .verify(token: "late") }
    }

    @Test func settlesOnlyOnce() async throws {
        let harness = try await WidgetHarness.loaded()
        let execution = try await harness.startExecution()

        try await harness.widgetCalls("onVerify", ["token-1"])
        try await harness.widgetCalls("onVerify", ["token-2"])
        try await harness.widgetCalls("onError", ["Something failed"])
        try await harness.widgetCalls("onClose")
        try await until { harness.events.last == .close }

        #expect(try await execution.token() == "token-1")
        let next = try await harness.startExecution()
        try await harness.widgetCalls("onVerify", ["token-3"])
        #expect(try await next.token() == "token-3")
    }

    @Test func resetSettlesIt() async throws {
        let harness = try await WidgetHarness.loaded()
        let execution = try await harness.startExecution()

        harness.bridge.reset()

        await #expect(throws: CaptchaFoxError(.reset)) { try await execution.token() }
        try await until { try await harness.page("return window.fake.resets") as? Int == 1 }
    }

    @Test func theEndOfTheWebViewsProcessSettlesItAndLoadsTheWidgetAgain() async throws {
        let harness = try await WidgetHarness.loaded()
        let execution = try await harness.startExecution()

        // WebKit's own way to end the process, as iOS does under memory pressure; not public API.
        let kill = NSSelectorFromString("_killWebContentProcess")
        try #require(harness.bridge.webView.responds(to: kill))
        harness.bridge.webView.perform(kill)

        // Requirements, because a web view whose process is gone and not reloaded never answers the steps below.
        try await #require(throws: CaptchaFoxError(.webContentTerminated)) { try await execution.token() }
        let tooEarly = Execution(harness.bridge)
        try await #require(throws: CaptchaFoxError(.notLoaded)) { try await tooEarly.token() }
        try await until { harness.events == [.load, .load] }
        let next = try await harness.startExecution()
        try await harness.widgetCalls("onVerify", ["token-after-reload"])
        #expect(try await next.token() == "token-after-reload")
    }

    @Test func throwsBeforeTheWidgetIsLoaded() async throws {
        let harness = WidgetHarness()

        await #expect(throws: CaptchaFoxError(.notLoaded)) { try await harness.bridge.execute() }
    }
}
