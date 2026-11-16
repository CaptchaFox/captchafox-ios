import CaptchaFox
import Foundation
import Testing
import UIKit

/// The widget from cdn.captchafox.com with the public test site keys, which work with any base URL.
@MainActor
struct LiveTests {
    /// The widget shows in a window of the app, as in an app: the process of a web view that shows nowhere stalls.
    private let window: UIWindow

    init() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        window = UIWindow(windowScene: scene)
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
    }

    @Test func theTestKeyThatPassesGivesATokenWithoutInteraction() async throws {
        let (view, events) = try await loadedWidget(siteKey: "sk_11111111000000001111111100000000")

        let token = try await withTimeout { try await view.execute() }

        #expect(!token.isEmpty)
        #expect(events.names == ["load", "verify"])
    }

    @Test func theTestKeyThatFailsGivesTheWidgetsError() async throws {
        let (view, events) = try await loadedWidget(siteKey: "sk_FFFFFFFF00000000FFFFFFFF00000000")

        await #expect {
            try await withTimeout { try await view.execute() }
        } throws: { error in
            (error as? CaptchaFoxError)?.code == .widget
        }
        #expect(events.names == ["load", "fail", "error"])
    }

    private func loadedWidget(siteKey: String) async throws -> (CaptchaFoxUIView, Events) {
        let configuration = CaptchaFoxConfiguration(siteKey: siteKey, baseURL: URL(string: "https://example.com/")!, mode: .hidden)
        let view = CaptchaFoxUIView(configuration: configuration)
        view.frame = CGRect(x: 20, y: 100, width: 300, height: 80)
        window.rootViewController?.view.addSubview(view)
        let events = Events()
        view.onLoad = { events.names.append("load") }
        view.onVerify = { _ in events.names.append("verify") }
        view.onError = { _ in events.names.append("error") }
        view.onFail = { events.names.append("fail") }
        view.onExpire = { events.names.append("expire") }
        view.onClose = { events.names.append("close") }
        view.onChallengeOpen = { events.names.append("challengeOpen") }

        try await withTimeout {
            while events.names.isEmpty {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        #expect(events.names == ["load"])
        return (view, events)
    }

    private func withTimeout<T: Sendable>(_ operation: @escaping @MainActor @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask(operation: operation)
            group.addTask {
                // On the first boot of a new simulator device, WebKit's processes take minutes to launch.
                try await Task.sleep(nanoseconds: 600_000_000_000)
                throw LiveTimeout()
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}

@MainActor
private final class Events {
    var names: [String] = []
}

private struct LiveTimeout: Error {}
