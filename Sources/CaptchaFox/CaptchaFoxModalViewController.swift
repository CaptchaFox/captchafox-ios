import UIKit

/// Shows the CaptchaFox widget over the current screen. Present it with `present(_:animated:)`; it shows a loading
/// indicator until the widget is loaded and dismisses itself on verify, error and close. In hidden mode it starts the
/// verification once the widget is loaded and shows the widget only when a challenge opens.
///
/// Set `backdropColor`, `headerView`, `footerView` and `loadingView` before presenting it.
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

    /// The colour over the presenting screen; by default black at 60 % opacity.
    public var backdropColor = UIColor.black.withAlphaComponent(0.6) {
        didSet {
            if isViewLoaded {
                view.backgroundColor = backdropColor
            }
        }
    }
    /// A view above the widget, such as a title.
    public var headerView: UIView?
    /// A view below the widget.
    public var footerView: UIView?
    /// Shown in place of the activity indicator while the widget loads, and in hidden mode until the token arrives.
    public var loadingView: UIView?

    /// Called once when the modal dismisses itself.
    var onFinish: (() -> Void)?
    /// View controllers whose views are the header, footer or loading view, added as children when the view loads.
    var hostedControllers: [UIViewController] = []

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

        view.backgroundColor = backdropColor
        for controller in hostedControllers {
            addChild(controller)
        }

        let loading = loadingView ?? loadingIndicator
        loadingIndicator.color = .white
        loadingIndicator.startAnimating()
        // Below the transparent web view: in hidden mode the challenge covers the loading view, which shows again when
        // the widget closes the challenge and checks the answer before it reports the token.
        let guide = view.safeAreaLayoutGuide
        for subview in [loading, widget] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            widget.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            widget.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            loading.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loading.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        var widgetTop = guide.topAnchor
        if let headerView {
            add(headerView, between: guide)
            headerView.topAnchor.constraint(equalTo: guide.topAnchor).isActive = true
            widgetTop = headerView.bottomAnchor
        }
        var widgetBottom = guide.bottomAnchor
        if let footerView {
            add(footerView, between: guide)
            footerView.bottomAnchor.constraint(equalTo: guide.bottomAnchor).isActive = true
            widgetBottom = footerView.topAnchor
        }
        widget.topAnchor.constraint(equalTo: widgetTop).isActive = true
        widget.bottomAnchor.constraint(equalTo: widgetBottom).isActive = true

        for controller in hostedControllers {
            controller.didMove(toParent: self)
        }
    }

    /// A header or footer spans the safe area's width at its own height.
    private func add(_ subview: UIView, between guide: UILayoutGuide) {
        subview.translatesAutoresizingMaskIntoConstraints = false
        subview.setContentHuggingPriority(.required, for: .vertical)
        subview.setContentCompressionResistancePriority(.required, for: .vertical)
        view.addSubview(subview)
        NSLayoutConstraint.activate([
            subview.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            subview.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
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
            loadingView?.isHidden = true
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
