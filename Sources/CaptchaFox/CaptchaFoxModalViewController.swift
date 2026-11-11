import UIKit

/// Shows the CaptchaFox widget over the current screen. Present it with `present(_:animated:)`; it shows a loading
/// indicator until the widget is loaded and dismisses itself on verify, error and close. In hidden mode it starts the
/// verification once the widget is loaded and shows the widget only when a challenge opens.
@MainActor
public final class CaptchaFoxModalViewController: UIViewController {
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

    /// Called once when the modal dismisses itself.
    var onFinish: (() -> Void)?

    /// Created when the view loads, so that nothing runs before the modal is presented.
    private(set) var widget: CaptchaFoxUIView?
    let loadingIndicator = UIActivityIndicatorView(style: .large)
    private let makeWidget: () -> CaptchaFoxUIView
    private let isHiddenMode: Bool
    private var execution: Task<Void, Never>?
    private var isFinished = false

    public convenience init(configuration: CaptchaFoxConfiguration) {
        self.init(mode: configuration.mode) {
            CaptchaFoxUIView(configuration: configuration)
        }
    }

    init(mode: CaptchaFoxConfiguration.Mode?, makeWidget: @escaping () -> CaptchaFoxUIView) {
        self.makeWidget = makeWidget
        isHiddenMode = mode == .hidden
        super.init(nibName: nil, bundle: nil)

        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CaptchaFoxModalViewController is created in code with init(configuration:).")
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        let widget = makeWidget()
        self.widget = widget
        widget.alpha = 0
        widget.onLoad = { [weak self] in
            self?.widgetLoaded()
        }
        widget.onVerify = { [weak self] token in
            self?.onVerify?(token)
            self?.finish()
        }
        widget.onError = { [weak self] message in
            self?.onError?(message)
            self?.finish()
        }
        widget.onFail = { [weak self] in
            self?.onFail?()
        }
        widget.onExpire = { [weak self] in
            self?.onExpire?()
        }
        widget.onClose = { [weak self] in
            self?.onClose?()
            self?.finish()
        }
        widget.onChallengeOpen = { [weak self] in
            self?.challengeOpened()
        }

        view.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        widget.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.color = .white
        loadingIndicator.startAnimating()
        // Below the transparent web view: in hidden mode the challenge covers the indicator, which shows again when the
        // widget closes the challenge and checks the answer before it reports the token.
        view.addSubview(loadingIndicator)
        view.addSubview(widget)
        NSLayoutConstraint.activate([
            widget.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            widget.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            widget.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            widget.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    override public func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        // A pending execute() would otherwise wait for a widget nobody sees.
        if isBeingDismissed {
            execution?.cancel()
        }
    }

    private func widgetLoaded() {
        onLoad?()

        if isHiddenMode, let widget {
            execution = Task { [weak self] in
                do {
                    // The widget's callbacks report a token and most errors.
                    _ = try await widget.execute()
                } catch is CancellationError {
                    // The modal cancelled it when it finished or was dismissed.
                } catch {
                    self?.executionFailed(error)
                }
            }
        } else {
            showWidget()
        }
    }

    private func challengeOpened() {
        onChallengeOpen?()

        if isHiddenMode {
            showWidget()
        }
    }

    /// The widget's `execute()` may fail without calling its error callback; once the modal has finished, the callback
    /// has reported the failure already.
    private func executionFailed(_ error: any Error) {
        guard !isFinished else {
            return
        }

        let captchaFoxError = error as? CaptchaFoxError
        onError?(captchaFoxError?.message ?? captchaFoxError?.code.rawValue ?? String(describing: error))
        finish()
    }

    private func showWidget() {
        if !isHiddenMode {
            loadingIndicator.stopAnimating()
        }
        widget?.alpha = 1
    }

    private func finish() {
        guard !isFinished else {
            return
        }

        isFinished = true
        execution?.cancel()
        onFinish?()
        presentingViewController?.dismiss(animated: true)
    }
}
