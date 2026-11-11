# CaptchaFox for iOS

Official [CaptchaFox](https://captchafox.com) integration for iOS. It shows the CaptchaFox widget in iOS apps and generates a token for backend verification.

## Compatibility

| iOS                    | Library |
| ---------------------- | ------- |
| 15, 16, 17, 18, 26, 27 | 1.x     |

Requires iOS 15 or later.

## Installation

In Xcode, choose **File > Add Package Dependencies…**, enter `https://github.com/CaptchaFox/captchafox-ios` and add the
library `CaptchaFox` to your app target. Or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/CaptchaFox/captchafox-ios", from: "1.0.0"),
],
targets: [
    .target(name: "YourApp", dependencies: [.product(name: "CaptchaFox", package: "captchafox-ios")]),
]
```

No dependencies besides Apple's frameworks.

## Configuration

### Get your keys

In the [CaptchaFox portal](https://portal.captchafox.com), create a site with the **iOS** integration, open it under
**Sites > Site Details** and copy the **site key** and the **domain**. The **secret key** of the site belongs on your
backend, never in the app.

### Set up the widget

```swift
import CaptchaFox

let configuration = CaptchaFoxConfiguration(
    siteKey: "YOUR_SITE_KEY",
    baseURL: URL(string: "https://YOUR_DOMAIN")!
)
```

### Options

| Option     | Default      | Meaning                                                                              |
| ---------- | ------------ | ------------------------------------------------------------------------------------ |
| `siteKey`  |              | The site key.                                                                        |
| `baseURL`  |              | The URL the widget is loaded with. Its host must be the site's domain in the portal. |
| `mode`     | the widget's | `.inline`, `.popup` or `.hidden`. Hidden stays invisible until a challenge opens.    |
| `theme`    | `.light`     | `.light` or `.dark`.                                                                 |
| `language` | detected     | A language code, such as `en` or `de`.                                               |

Options left `nil` use the widget's default.

## Usage

Send the token to your backend with the request it protects. The backend verifies it with the site's secret key (see
[Verify the Response Token on the Server](https://docs.captchafox.com/getting-started#verify-the-response-token-on-the-server))
and processes the request only if the verification passes.

[`Example/`](Example) holds a SwiftUI app that uses the package with the public test keys or your own site key. Open
`Example/CaptchaFoxExample.xcodeproj` in Xcode and run it.

### Modal

Shows the widget over the current screen and closes on verify, error or close. In hidden mode it starts the
verification itself and only appears if a challenge opens.

UIKit:

```swift
let captcha = CaptchaFoxModalViewController(configuration: configuration)
captcha.onVerify = { token in
    // Send the token to your backend.
}
captcha.onError = { message in
    // Show the error or let the user retry.
}
present(captcha, animated: true)
```

SwiftUI:

```swift
@State private var showsCaptcha = false

var body: some View {
    Button("Sign up") { showsCaptcha = true }
        .captchaFoxModal(isPresented: $showsCaptcha, configuration: configuration, onVerify: { token in
            // Send the token to your backend.
        })
}
```

### View

`CaptchaFoxUIView` (UIKit) and `CaptchaFoxView` (SwiftUI) put the widget in your layout. `CaptchaFoxView` supports
inline and popup; for hidden mode in SwiftUI, use `captchaFoxModal`. `CaptchaFoxUIView` also has `execute()`, which
returns the token, and `reset()`:

```swift
let captcha = CaptchaFoxUIView(configuration: configuration)
captcha.onLoad = { /* From now on execute() works. */ }
view.addSubview(captcha)

do {
    let token = try await captcha.execute()
    // Send the token to your backend.
} catch let error as CaptchaFoxError where error.code == .closed {
    // The user closed the challenge.
} catch {
    // Another CaptchaFoxError, or CancellationError.
}
```

`execute()` returns the token or throws a `CaptchaFoxError` with one of these codes:

| Code                    | When                                                                          |
| ----------------------- | ----------------------------------------------------------------------------- |
| `.widget`               | The widget reported an error, see `message`.                                  |
| `.closed`               | The user closed the challenge.                                                |
| `.superseded`           | `execute()` was called again.                                                 |
| `.reset`                | `reset()` was called.                                                         |
| `.notLoaded`            | It was called before `onLoad`, for example because the script failed to load. |
| `.webContentTerminated` | iOS ended the web view's process; the widget reloads.                         |

If the calling task is cancelled, it throws `CancellationError`. Minor versions may add codes, so a `switch` over `code`
needs a `default` case.

### Callbacks

The modal, both views and `captchaFoxModal` take the same callbacks, called on the main thread:

| Callback           | Called when                                          |
| ------------------ | ---------------------------------------------------- |
| `onLoad`           | The widget is rendered.                              |
| `onVerify(token)`  | The user is verified.                                |
| `onError(message)` | An error occurs, for example the widget cannot load. |
| `onFail`           | The user failed the challenge.                       |
| `onExpire`         | The token expired before it was used.                |
| `onClose`          | The user closed the challenge.                       |
| `onChallengeOpen`  | A challenge opens, also in hidden mode.              |

## Operation

### If CaptchaFox is unreachable

If the widget's script cannot be loaded from cdn.captchafox.com, or the widget cannot reach CaptchaFox, you get
`onError` or `execute()` throws (`.notLoaded` or `.widget`), and the modal closes. Without a token, your backend decides
whether the request goes through.

### Log

The library logs nothing.

### Links in the widget

The web view shows only the widget. Links tapped in it open in the system browser.

### Privacy

CaptchaFox is operated by Scoria Labs GmbH, Germany. How CaptchaFox processes data and how to get a data processing
agreement is described in the [CaptchaFox Privacy Center](https://captchafox.com/privacy). A suggested paragraph for
your privacy policy is on the [GDPR page](https://captchafox.com/privacy/gdpr).

## License

MIT. See [LICENSE](LICENSE).
