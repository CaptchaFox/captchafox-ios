// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CaptchaFox",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "CaptchaFox", targets: ["CaptchaFox"]),
    ],
    targets: [
        .target(name: "CaptchaFox"),
        .testTarget(name: "CaptchaFoxTests", dependencies: ["CaptchaFox"]),
        // Uses the package only through `import CaptchaFox`, as an app does.
        .testTarget(name: "PublicInterfaceTests", dependencies: ["CaptchaFox"]),
        // Loads the widget from cdn.captchafox.com; run apart from the other tests.
        .testTarget(name: "LiveTests", dependencies: ["CaptchaFox"]),
    ]
)
