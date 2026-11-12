import Testing
import UIKit
@testable import CaptchaFox

@MainActor
struct ViewTests {
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
}
