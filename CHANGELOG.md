## 1.0.0

- Show the CaptchaFox widget in iOS apps and hand its token to the app: `CaptchaFoxUIView` (UIKit), `CaptchaFoxView`
  (SwiftUI) and a modal (`CaptchaFoxModalViewController`, `captchaFoxModal`, also for hidden mode); `execute()` returns
  the token or throws a `CaptchaFoxError` with a code.
- The modal takes a backdrop colour, a header, a footer, a loading view and a delay before it closes after verify.
- The views show an activity indicator until the widget has loaded; `showsLoadingIndicator` turns it off.
- iOS 15 and later, Xcode 16 and later, no dependencies.
- An example app in `Example/`.
