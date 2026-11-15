import Foundation
import Testing
@testable import CaptchaFox

@MainActor
struct WidgetPageTests {
    init() async throws {
        try await WebKitWarmUp.ready()
    }

    @Test func theOptionsReachTheWidgetAsData() async throws {
        // `<!--<script>` puts the HTML parser into a state in which even an escaped `</script>` no longer ends the element.
        let siteKey = #"sk_"</script><!--<script>window.injected = true</script>"#
        let configuration = CaptchaFoxConfiguration(siteKey: siteKey, baseURL: WidgetHarness.baseURL, mode: .hidden, theme: .dark, language: "de")
        let harness = try await WidgetHarness.loaded(configuration: configuration)

        #expect(try await renderedOptions(harness) == ["sitekey": siteKey, "mode": "hidden", "theme": "dark", "lang": "de"])
        #expect(try await harness.page("return typeof window.injected") as? String == "undefined")
    }

    @Test func unsetOptionsAreLeftOut() async throws {
        let harness = try await WidgetHarness.loaded()

        #expect(try await renderedOptions(harness) == ["sitekey": "sk_test"])
    }

    @Test func aScriptThatDoesNotLoadIsAnError() async throws {
        let harness = WidgetHarness(scriptURL: URL(string: "unreachable://cdn.example/api.js")!)

        try await until { !harness.events.isEmpty }

        #expect(harness.events == [.error("The CaptchaFox script could not be loaded.")])
        await #expect(throws: CaptchaFoxError(.notLoaded)) { try await harness.bridge.execute() }
    }

    /// The options the page passed to the widget's `render`, without the callbacks.
    private func renderedOptions(_ harness: WidgetHarness) async throws -> [String: String] {
        let json = try #require(try await harness.page("return JSON.stringify(window.fake.options)") as? String)
        return try JSONDecoder().decode([String: String].self, from: Data(json.utf8))
    }
}
