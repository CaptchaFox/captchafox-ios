import SwiftUI

/// The CaptchaFox widget as a SwiftUI view. A changed configuration loads the widget anew.
public struct CaptchaFoxView: View {
    private let configuration: CaptchaFoxConfiguration
    private let showsLoadingIndicator: Bool
    private let callbacks: Callbacks

    /// - Parameters:
    ///   - showsLoadingIndicator: Whether an activity indicator shows until the widget is loaded or reports an error.
    ///   - onVerify: Called with the token, which your backend verifies.
    ///   - onError: Called with the widget's error message.
    ///   - onFail: Called when the visitor failed the challenge.
    ///   - onExpire: Called when the token expired before it was used.
    ///   - onClose: Called when the visitor closed the challenge.
    ///   - onChallengeOpen: Called when a challenge opens, also in hidden mode.
    public init(
        configuration: CaptchaFoxConfiguration,
        showsLoadingIndicator: Bool = true,
        onLoad: (() -> Void)? = nil,
        onVerify: ((String) -> Void)? = nil,
        onError: ((String) -> Void)? = nil,
        onFail: (() -> Void)? = nil,
        onExpire: (() -> Void)? = nil,
        onClose: (() -> Void)? = nil,
        onChallengeOpen: (() -> Void)? = nil
    ) {
        self.configuration = configuration
        self.showsLoadingIndicator = showsLoadingIndicator
        callbacks = Callbacks(
            onLoad: onLoad,
            onVerify: onVerify,
            onError: onError,
            onFail: onFail,
            onExpire: onExpire,
            onClose: onClose,
            onChallengeOpen: onChallengeOpen
        )
    }

    public var body: some View {
        WidgetRepresentable(configuration: configuration, showsLoadingIndicator: showsLoadingIndicator, callbacks: callbacks)
            .id(configuration)
    }
}

extension View {
    /// Shows the CaptchaFox widget over the current screen while `isPresented` is true, as
    /// `CaptchaFoxModalViewController` does, and sets `isPresented` to false when it dismisses itself.
    ///
    /// - Parameters:
    ///   - backdropColor: The colour over the current screen.
    ///   - dismissDelayAfterVerify: How many seconds the modal stays after verify, so that the visitor sees the
    ///     widget's success state; 0 dismisses it at once. `onVerify` is called at once either way.
    ///   - header: A view above the widget, such as a title.
    ///   - footer: A view below the widget.
    ///   - loading: Shown in place of the activity indicator while the widget loads, and in hidden mode until the token
    ///     arrives; `EmptyView` keeps the activity indicator.
    ///   - onVerify: Called with the token, which your backend verifies.
    ///   - onError: Called with the widget's error message.
    ///   - onFail: Called when the visitor failed the challenge.
    ///   - onExpire: Called when the token expired before it was used.
    ///   - onClose: Called when the visitor closed the challenge.
    ///   - onChallengeOpen: Called when a challenge opens, also in hidden mode.
    public func captchaFoxModal<Header: View, Footer: View, Loading: View>(
        isPresented: Binding<Bool>,
        configuration: CaptchaFoxConfiguration,
        backdropColor: Color = Color.black.opacity(0.6),
        dismissDelayAfterVerify: TimeInterval = 0.5,
        @ViewBuilder header: () -> Header = { EmptyView() },
        @ViewBuilder footer: () -> Footer = { EmptyView() },
        @ViewBuilder loading: () -> Loading = { EmptyView() },
        onLoad: (() -> Void)? = nil,
        onVerify: ((String) -> Void)? = nil,
        onError: ((String) -> Void)? = nil,
        onFail: (() -> Void)? = nil,
        onExpire: (() -> Void)? = nil,
        onClose: (() -> Void)? = nil,
        onChallengeOpen: (() -> Void)? = nil
    ) -> some View {
        background(ModalPresenter(
            isPresented: isPresented,
            configuration: configuration,
            style: ModalStyle(
                backdropColor: UIColor(backdropColor),
                dismissDelayAfterVerify: dismissDelayAfterVerify,
                header: ModalStyle.content(header()),
                footer: ModalStyle.content(footer()),
                loading: ModalStyle.content(loading())
            ),
            callbacks: Callbacks(
                onLoad: onLoad,
                onVerify: onVerify,
                onError: onError,
                onFail: onFail,
                onExpire: onExpire,
                onClose: onClose,
                onChallengeOpen: onChallengeOpen
            )
        ))
    }
}

private struct Callbacks {
    var onLoad: (() -> Void)?
    var onVerify: ((String) -> Void)?
    var onError: ((String) -> Void)?
    var onFail: (() -> Void)?
    var onExpire: (() -> Void)?
    var onClose: (() -> Void)?
    var onChallengeOpen: (() -> Void)?

    @MainActor
    func assign(to view: CaptchaFoxUIView) {
        view.onLoad = onLoad
        view.onVerify = onVerify
        view.onError = onError
        view.onFail = onFail
        view.onExpire = onExpire
        view.onClose = onClose
        view.onChallengeOpen = onChallengeOpen
    }

    @MainActor
    func assign(to modal: CaptchaFoxModalViewController) {
        modal.onLoad = onLoad
        modal.onVerify = onVerify
        modal.onError = onError
        modal.onFail = onFail
        modal.onExpire = onExpire
        modal.onClose = onClose
        modal.onChallengeOpen = onChallengeOpen
    }
}

private struct WidgetRepresentable: UIViewRepresentable {
    let configuration: CaptchaFoxConfiguration
    let showsLoadingIndicator: Bool
    let callbacks: Callbacks

    func makeUIView(context: Context) -> CaptchaFoxUIView {
        CaptchaFoxUIView(configuration: configuration)
    }

    func updateUIView(_ view: CaptchaFoxUIView, context: Context) {
        view.showsLoadingIndicator = showsLoadingIndicator
        callbacks.assign(to: view)
    }
}

/// The modal's backdrop colour and the SwiftUI views it shows in place of none or of its activity indicator.
private struct ModalStyle {
    var backdropColor: UIColor
    var dismissDelayAfterVerify: TimeInterval
    var header: AnyView?
    var footer: AnyView?
    var loading: AnyView?

    /// `nil` for `EmptyView`, which stands for no view or the default one.
    static func content<Content: View>(_ view: Content) -> AnyView? {
        Content.self == EmptyView.self ? nil : AnyView(view)
    }
}

/// Presents the modal from an invisible view controller in the hierarchy of the view it is attached to.
private struct ModalPresenter: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let configuration: CaptchaFoxConfiguration
    let style: ModalStyle
    let callbacks: Callbacks

    final class Coordinator {
        var modal: CaptchaFoxModalViewController?
        var hosts: [KeyPath<ModalStyle, AnyView?>: UIHostingController<AnyView>] = [:]
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ anchor: UIViewController, context: Context) {
        let coordinator = context.coordinator
        if let modal = coordinator.modal {
            callbacks.assign(to: modal)
            modal.backdropColor = style.backdropColor
            modal.dismissDelayAfterVerify = style.dismissDelayAfterVerify
            for (keyPath, host) in coordinator.hosts {
                if let content = style[keyPath: keyPath] {
                    host.rootView = content
                }
            }
            if !isPresented {
                coordinator.modal = nil
                modal.dismiss(animated: true)
            }
            return
        }

        guard isPresented else {
            return
        }

        let modal = CaptchaFoxModalViewController(configuration: configuration)
        callbacks.assign(to: modal)
        modal.backdropColor = style.backdropColor
        modal.dismissDelayAfterVerify = style.dismissDelayAfterVerify
        coordinator.hosts = [:]
        let slots: [(KeyPath<ModalStyle, AnyView?>, ReferenceWritableKeyPath<CaptchaFoxModalViewController, UIView?>)] = [
            (\.header, \.headerView),
            (\.footer, \.footerView),
            (\.loading, \.loadingView),
        ]
        for (keyPath, viewPath) in slots {
            guard let content = style[keyPath: keyPath] else {
                continue
            }

            let host = UIHostingController(rootView: content)
            host.view.backgroundColor = .clear
            if #available(iOS 16.0, *) {
                host.sizingOptions = .intrinsicContentSize
            }
            coordinator.hosts[keyPath] = host
            modal.hostedControllers.append(host)
            modal[keyPath: viewPath] = host.view
        }
        let isPresented = $isPresented
        modal.onFinish = { [weak coordinator] in
            coordinator?.modal = nil
            isPresented.wrappedValue = false
        }
        coordinator.modal = modal
        anchor.present(modal, animated: true)
    }
}
