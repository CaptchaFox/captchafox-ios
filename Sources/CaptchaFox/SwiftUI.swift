import SwiftUI

/// The CaptchaFox widget as a SwiftUI view. A changed configuration loads the widget anew.
public struct CaptchaFoxView: View {
    private let configuration: CaptchaFoxConfiguration
    private let callbacks: Callbacks

    /// - Parameters:
    ///   - onVerify: Called with the token, which your backend verifies.
    ///   - onError: Called with the widget's error message.
    ///   - onFail: Called when the visitor failed the challenge.
    ///   - onExpire: Called when the token expired before it was used.
    ///   - onClose: Called when the visitor closed the challenge.
    ///   - onChallengeOpen: Called when a challenge opens, also in hidden mode.
    public init(
        configuration: CaptchaFoxConfiguration,
        onLoad: (() -> Void)? = nil,
        onVerify: ((String) -> Void)? = nil,
        onError: ((String) -> Void)? = nil,
        onFail: (() -> Void)? = nil,
        onExpire: (() -> Void)? = nil,
        onClose: (() -> Void)? = nil,
        onChallengeOpen: (() -> Void)? = nil
    ) {
        self.configuration = configuration
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
        WidgetRepresentable(configuration: configuration, callbacks: callbacks)
            .id(configuration)
    }
}

extension View {
    /// Shows the CaptchaFox widget over the current screen while `isPresented` is true, as
    /// `CaptchaFoxModalViewController` does, and sets `isPresented` to false when it dismisses itself.
    ///
    /// - Parameters:
    ///   - onVerify: Called with the token, which your backend verifies.
    ///   - onError: Called with the widget's error message.
    ///   - onFail: Called when the visitor failed the challenge.
    ///   - onExpire: Called when the token expired before it was used.
    ///   - onClose: Called when the visitor closed the challenge.
    ///   - onChallengeOpen: Called when a challenge opens, also in hidden mode.
    public func captchaFoxModal(
        isPresented: Binding<Bool>,
        configuration: CaptchaFoxConfiguration,
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
    let callbacks: Callbacks

    func makeUIView(context: Context) -> CaptchaFoxUIView {
        CaptchaFoxUIView(configuration: configuration)
    }

    func updateUIView(_ view: CaptchaFoxUIView, context: Context) {
        callbacks.assign(to: view)
    }
}

/// Presents the modal from an invisible view controller in the hierarchy of the view it is attached to.
private struct ModalPresenter: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let configuration: CaptchaFoxConfiguration
    let callbacks: Callbacks

    final class Coordinator {
        var modal: CaptchaFoxModalViewController?
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
        let isPresented = $isPresented
        modal.onFinish = { [weak coordinator] in
            coordinator?.modal = nil
            isPresented.wrappedValue = false
        }
        coordinator.modal = modal
        anchor.present(modal, animated: true)
    }
}
