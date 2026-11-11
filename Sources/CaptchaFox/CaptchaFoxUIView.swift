import UIKit

/// The CaptchaFox widget as a UIKit view. It loads the widget when it is created; the callbacks are called on the main
/// thread.
@MainActor
public final class CaptchaFoxUIView: UIView {
    public var onLoad: (() -> Void)?
    /// Called with the token, which your backend verifies.
    public var onVerify: ((String) -> Void)?
    /// Called with the widget's error message.
    public var onError: ((String) -> Void)?
    /// Called when the visitor failed the challenge.
    public var onFail: (() -> Void)?
    /// Called when the token expired before it was used.
    public var onExpire: (() -> Void)?
    /// Called when the visitor closed the challenge.
    public var onClose: (() -> Void)?
    /// Called when a challenge opens, also in hidden mode.
    public var onChallengeOpen: (() -> Void)?

    private let bridge: WidgetBridge

    public convenience init(configuration: CaptchaFoxConfiguration) {
        self.init(bridge: WidgetBridge(configuration: configuration))
    }

    init(bridge: WidgetBridge) {
        self.bridge = bridge
        super.init(frame: .zero)

        bridge.webView.frame = bounds
        bridge.webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(bridge.webView)
        bridge.onEvent = { [weak self] event in
            self?.deliver(event)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CaptchaFoxUIView is created in code with init(configuration:).")
    }

    /// Starts the verification, as hidden mode needs it, and returns the token once the widget has one. It throws
    /// `CaptchaFoxError` before the widget is loaded, when the widget reports an error, when the visitor closes the
    /// challenge and when `execute()` is called again, and `CancellationError` when the calling task is cancelled.
    public func execute() async throws -> String {
        try await bridge.execute()
    }

    /// Resets the widget, so that the visitor verifies again.
    public func reset() {
        bridge.reset()
    }

    private func deliver(_ event: WidgetEvent) {
        switch event {
        case .load:
            onLoad?()
        case .verify(let token):
            onVerify?(token)
        case .error(let message):
            onError?(message)
        case .fail:
            onFail?()
        case .expire:
            onExpire?()
        case .close:
            onClose?()
        case .challengeOpen:
            onChallengeOpen?()
        }
    }
}
