import Foundation

/// What the widget shows and for which site. An option that is `nil` is not passed to the widget, so its default holds.
public struct CaptchaFoxConfiguration: Hashable, Sendable {
    /// How the widget is shown. New modes may be added in a minor version.
    public struct Mode: RawRepresentable, Hashable, Sendable {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public static let inline = Mode(rawValue: "inline")
        public static let popup = Mode(rawValue: "popup")
        /// Invisible until a challenge opens; `execute()` starts the verification.
        public static let hidden = Mode(rawValue: "hidden")
    }

    /// The widget's colours. New themes may be added in a minor version.
    public struct Theme: RawRepresentable, Hashable, Sendable {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public static let light = Theme(rawValue: "light")
        public static let dark = Theme(rawValue: "dark")
    }

    public var siteKey: String
    /// The URL the widget's page is loaded with. Its host must be the domain set up for the site in the CaptchaFox portal.
    public var baseURL: URL
    public var mode: Mode?
    public var theme: Theme?
    /// A language code such as `en` or `de`; by default the widget detects the language.
    public var language: String?

    public init(siteKey: String, baseURL: URL, mode: Mode? = nil, theme: Theme? = nil, language: String? = nil) {
        self.siteKey = siteKey
        self.baseURL = baseURL
        self.mode = mode
        self.theme = theme
        self.language = language
    }
}
