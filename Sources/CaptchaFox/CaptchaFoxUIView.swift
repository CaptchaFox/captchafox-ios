import UIKit

/// The CaptchaFox widget as a UIKit view. It loads the widget when it is created; the callbacks are called on the main
/// thread. While a challenge is open, it shows the widget over its whole window.
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

    /// Whether an activity indicator shows until the widget is loaded or reports an error; `true` by default.
    public var showsLoadingIndicator = true {
        didSet {
            updateLoadingIndicator()
        }
    }

    /// After a visual challenge, the widget shows its success state for a second after it calls `onVerify`.
    static let challengeEndDelayAfterVerify: TimeInterval = 1

    /// Whether an opened challenge moves to an overlay over the window; off in the modal, which fills the screen already.
    var showsChallengeFullScreen = true

    let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let bridge: WidgetBridge
    private var isLoading = true
    private var isChallengeOpen = false {
        didSet {
            updateOverlay()
        }
    }
    private var challengeEnd: Task<Void, Never>?
    /// A view over the whole window rather than a presented controller, so that the app can still present its own.
    private(set) var overlay: UIView?

    public convenience init(configuration: CaptchaFoxConfiguration) {
        self.init(bridge: WidgetBridge(configuration: configuration))
    }

    init(bridge: WidgetBridge) {
        self.bridge = bridge
        super.init(frame: .zero)

        bridge.webView.frame = bounds
        bridge.webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(bridge.webView)
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(loadingIndicator)
        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        updateLoadingIndicator()
        bridge.onEvent = { [weak self] event in
            self?.deliver(event)
        }
        bridge.onWebContentTerminated = { [weak self] in
            self?.endChallenge()
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
        endChallenge()
    }

    override public func didMoveToWindow() {
        super.didMoveToWindow()

        updateOverlay()
    }

    private func updateLoadingIndicator() {
        if showsLoadingIndicator && isLoading {
            loadingIndicator.startAnimating()
        } else {
            loadingIndicator.stopAnimating()
        }
    }

    private func deliver(_ event: WidgetEvent) {
        if case .load = event {
            isLoading = false
        } else if case .error = event {
            isLoading = false
        }
        updateLoadingIndicator()

        // The overlay changes before the app's callback, so that what the app presents in it shows above the overlay.
        switch event {
        case .load:
            onLoad?()
        case .verify(let token):
            endChallenge(after: Self.challengeEndDelayAfterVerify)
            onVerify?(token)
        case .error(let message):
            endChallenge()
            onError?(message)
        case .fail:
            endChallenge()
            onFail?()
        case .expire:
            // The widget also expires a challenge left open too long.
            endChallenge()
            onExpire?()
        case .close:
            endChallenge()
            onClose?()
        case .challengeOpen:
            challengeEnd?.cancel()
            challengeEnd = nil
            isChallengeOpen = true
            onChallengeOpen?()
        }
    }

    /// Ends the challenge at once, or after `delay` unless it opens again before.
    private func endChallenge(after delay: TimeInterval = 0) {
        challengeEnd?.cancel()
        challengeEnd = nil
        guard isChallengeOpen else {
            return
        }

        guard delay > 0 else {
            isChallengeOpen = false
            return
        }

        var end: Task<Void, Never>?
        end = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else {
                return
            }

            if challengeEnd == end {
                challengeEnd = nil
            }
            isChallengeOpen = false
        }
        challengeEnd = end
    }

    /// The web view is in the overlay while a challenge is open and the view is in a window.
    private func updateOverlay() {
        let showsOverlay = showsChallengeFullScreen && isChallengeOpen && window != nil
        switch (showsOverlay, overlay) {
        case (true, nil):
            showOverlay()
        case (false, let shown?):
            overlay = nil
            shown.removeFromSuperview()
            returnWebView()
        case (true, _?), (false, nil):
            break
        }
    }

    /// Covers the whole window with the modal's default backdrop and shows the web view within the safe area, above the
    /// window's content at this moment; what the app presents later shows above it.
    private func showOverlay() {
        guard let window else {
            return
        }

        let shown = UIView(frame: window.bounds)
        shown.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        shown.backgroundColor = CaptchaFoxModalViewController.defaultBackdropColor
        shown.accessibilityViewIsModal = true
        let webView = bridge.webView
        webView.translatesAutoresizingMaskIntoConstraints = false
        shown.addSubview(webView)
        let guide = shown.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            webView.topAnchor.constraint(equalTo: guide.topAnchor),
            webView.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
        ])
        window.addSubview(shown)
        overlay = shown
    }

    private func returnWebView() {
        let webView = bridge.webView
        webView.translatesAutoresizingMaskIntoConstraints = true
        webView.frame = bounds
        insertSubview(webView, belowSubview: loadingIndicator)
    }
}
