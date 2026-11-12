import CaptchaFox
import Foundation
import SwiftUI
import Testing
import UIKit

/// Uses the package only as an app does. A change that breaks an app's code breaks the build of this target.
@MainActor
struct PublicInterfaceTests {
    private let configuration = CaptchaFoxConfiguration(
        siteKey: "sk_11111111000000001111111100000000",
        baseURL: URL(string: "https://example.com/")!,
        mode: .hidden,
        theme: .dark,
        language: "de"
    )

    @Test func configurationOptions() {
        var configuration = CaptchaFoxConfiguration(siteKey: "sk_11111111000000001111111100000000", baseURL: URL(string: "https://example.com/")!)
        #expect(configuration.mode == nil)
        #expect(configuration.theme == nil)
        #expect(configuration.language == nil)

        configuration.mode = .popup
        configuration.theme = .light
        configuration.language = "en"
        #expect(configuration != self.configuration)
        #expect(Set([configuration, self.configuration]).count == 2)
    }

    @Test func modesAndThemes() {
        let modes: [CaptchaFoxConfiguration.Mode] = [.inline, .popup, .hidden]
        #expect(modes.map(\.rawValue) == ["inline", "popup", "hidden"])
        #expect(CaptchaFoxConfiguration.Mode(rawValue: "hidden") == .hidden)

        let themes: [CaptchaFoxConfiguration.Theme] = [.light, .dark]
        #expect(themes.map(\.rawValue) == ["light", "dark"])
        #expect(CaptchaFoxConfiguration.Theme(rawValue: "dark") == .dark)

        let handled = modes.map { mode -> String in
            switch mode {
            case .hidden:
                "hidden"
            default:
                "shown"
            }
        }
        #expect(handled == ["shown", "shown", "hidden"])
    }

    @Test func uiKitView() async {
        let widget = CaptchaFoxUIView(configuration: configuration)
        let _: UIView = widget
        #expect(widget.showsLoadingIndicator)
        widget.showsLoadingIndicator = false

        widget.onLoad = {}
        widget.onVerify = { (_: String) in }
        widget.onError = { (_: String) in }
        widget.onFail = {}
        widget.onExpire = {}
        widget.onClose = {}
        widget.onChallengeOpen = {}
        widget.reset()
        await #expect(throws: CaptchaFoxError(.notLoaded)) {
            let _: String = try await widget.execute()
        }
    }

    @Test func modal() {
        let captcha = CaptchaFoxModalViewController(configuration: configuration)
        let _: UIViewController = captcha

        captcha.onLoad = {}
        captcha.onVerify = { (_: String) in }
        captcha.onError = { (_: String) in }
        captcha.onFail = {}
        captcha.onExpire = {}
        captcha.onClose = {}
        captcha.onChallengeOpen = {}
        #expect(captcha.modalPresentationStyle == .overFullScreen)

        #expect(captcha.backdropColor == UIColor.black.withAlphaComponent(0.6))
        #expect(captcha.headerView == nil && captcha.footerView == nil && captcha.loadingView == nil)
        captcha.backdropColor = .black
        captcha.headerView = UILabel()
        captcha.footerView = UILabel()
        captcha.loadingView = UIActivityIndicatorView()
        #expect(captcha.dismissDelayAfterVerify == 0.5)
        captcha.dismissDelayAfterVerify = 0
    }

    @Test func swiftUI() {
        let view = CaptchaFoxView(
            configuration: configuration,
            onLoad: {},
            onVerify: { (_: String) in },
            onError: { (_: String) in },
            onFail: {},
            onExpire: {},
            onClose: {},
            onChallengeOpen: {}
        )
        let modal = Text("Sign up").captchaFoxModal(
            isPresented: .constant(false),
            configuration: configuration,
            onLoad: {},
            onVerify: { (_: String) in },
            onError: { (_: String) in },
            onFail: {},
            onExpire: {},
            onClose: {},
            onChallengeOpen: {}
        )
        let minimal = VStack {
            CaptchaFoxView(configuration: configuration)
            CaptchaFoxView(configuration: configuration, showsLoadingIndicator: false)
        }
        .captchaFoxModal(isPresented: .constant(false), configuration: configuration)
        let styled = Text("Sign up").captchaFoxModal(
            isPresented: .constant(false),
            configuration: configuration,
            backdropColor: .black.opacity(0.8),
            dismissDelayAfterVerify: 1,
            header: { Text("Verify") },
            footer: { Text("Protected by CaptchaFox") },
            loading: { ProgressView() },
            onVerify: { (_: String) in }
        )

        _ = (view, modal, minimal, styled)
    }

    @Test func errors() async {
        let codes: [CaptchaFoxError.Code] = [.notLoaded, .widget, .closed, .superseded, .reset, .webContentTerminated]
        #expect(Set(codes).count == codes.count)
        #expect(CaptchaFoxError.Code(rawValue: CaptchaFoxError.Code.closed.rawValue) == .closed)

        let error = CaptchaFoxError(.widget, message: "message")
        #expect(error.code == .widget)
        #expect(error.message == "message")
        #expect(CaptchaFoxError(.closed).message == nil)
        #expect(error != CaptchaFoxError(.widget))

        let widget = CaptchaFoxUIView(configuration: configuration)
        do {
            _ = try await widget.execute()
            Issue.record("execute() returned a token before the widget was loaded")
        } catch let error as CaptchaFoxError where error.code == .notLoaded {
            #expect(error.message == nil)
        } catch {
            Issue.record("unexpected error \(error)")
        }

        let handled = codes.map { code -> String in
            switch code {
            case .closed:
                "closed"
            default:
                "other"
            }
        }
        #expect(handled.filter { $0 == "closed" }.count == 1)
    }
}
