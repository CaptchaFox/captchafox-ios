// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CaptchaFox",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "CaptchaFox", targets: ["CaptchaFox"]),
    ],
    targets: [
        // The tests are targets of Tests/TestHost.xcodeproj: WebKit runs pages reliably only in an app.
        .target(name: "CaptchaFox"),
    ]
)
