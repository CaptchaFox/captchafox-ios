import Testing
@testable import CaptchaFox

@MainActor
struct MessageTests {
    init() async throws {
        try await WebKitWarmUp.ready()
    }

    @Test func eachEventReachesTheView() async throws {
        let harness = WidgetHarness()
        let view = CaptchaFoxUIView(bridge: harness.bridge)
        var received: [String] = []
        view.onLoad = { received.append("load") }
        view.onVerify = { received.append("verify \($0)") }
        view.onError = { received.append("error \($0)") }
        view.onFail = { received.append("fail") }
        view.onExpire = { received.append("expire") }
        view.onClose = { received.append("close") }
        view.onChallengeOpen = { received.append("challengeOpen") }
        try await until { received == ["load"] }

        try await harness.widgetCalls("onChallengeOpen")
        try await harness.widgetCalls("onFail")
        try await harness.widgetCalls("onVerify", ["token-1"])
        try await harness.widgetCalls("onExpire")
        try await harness.widgetCalls("onClose")
        try await harness.widgetCalls("onError", ["Something failed"])
        try await until { received.count == 7 }

        #expect(received == ["load", "challengeOpen", "fail", "verify token-1", "expire", "close", "error Something failed"])
    }

    @Test func resetResetsTheWidget() async throws {
        let harness = try await WidgetHarness.loaded()
        let view = CaptchaFoxUIView(bridge: harness.bridge)

        view.reset()

        try await until { try await harness.page("return window.fake.resets") as? Int == 1 }
    }

    @Test func aMessageFromAFrameInsideThePageIsIgnored() async throws {
        let harness = try await WidgetHarness.loaded()
        let execution = try await harness.startExecution()

        let posted = try await harness.page("""
            var frame = document.createElement('iframe');
            frame.srcdoc = '<script>window.webkit.messageHandlers.captchafox.postMessage({ type: "verify", token: "from-frame" }); parent.fake.framePosted = true;<\\/script>';
            await new Promise(function (resolve) { frame.onload = resolve; document.body.appendChild(frame); });
            return window.fake.framePosted === true;
            """)
        #expect(posted as? Bool == true)
        try await harness.post(["type": "fail"])
        try await until { harness.events.last == .fail }

        #expect(harness.events == [.load, .fail])
        #expect(execution.result == nil)
        try await harness.widgetCalls("onVerify", ["from-widget"])
        #expect(try await execution.token() == "from-widget")
    }

    @Test func aMessageOfNoKnownFormIsIgnored() async throws {
        let harness = try await WidgetHarness.loaded()
        let execution = try await harness.startExecution()

        try await harness.post(["type": "VERIFY", "token": "upper-case"])
        try await harness.post(["type": "token", "token": "unknown-type"])
        try await harness.post(#"{"type":"verify","token":"string"}"#)
        try await harness.post(["type": "verify"])
        try await harness.post(["type": "verify", "token": ""])
        try await harness.post(["type": "verify", "token": 42])
        try await harness.post(["token": "no-type"])
        try await harness.post(["type": "fail"])
        try await until { harness.events.last == .fail }

        #expect(harness.events == [.load, .fail])
        #expect(execution.result == nil)
        try await harness.widgetCalls("onVerify", ["from-widget"])
        #expect(try await execution.token() == "from-widget")
    }
}
