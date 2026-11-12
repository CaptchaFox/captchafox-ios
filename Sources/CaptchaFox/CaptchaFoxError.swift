/// Why `execute()` returned no token. A cancelled calling task gets `CancellationError` instead.
public struct CaptchaFoxError: Error, Equatable, Sendable {
    /// The kind of error. New codes may be added in a minor version.
    public struct Code: RawRepresentable, Hashable, Sendable {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        /// The widget has not reported that it is loaded.
        public static let notLoaded = Code(rawValue: "notLoaded")
        /// The widget reported an error; `message` holds its message.
        public static let widget = Code(rawValue: "widget")
        /// The visitor closed the challenge.
        public static let closed = Code(rawValue: "closed")
        /// `execute()` was called again before this call settled.
        public static let superseded = Code(rawValue: "superseded")
        /// `reset()` was called before this call settled.
        public static let reset = Code(rawValue: "reset")
        /// The web view's process ended, as iOS may end it under memory pressure; the widget loads again.
        public static let webContentTerminated = Code(rawValue: "webContentTerminated")
    }

    public let code: Code
    /// The widget's message, where it gave one.
    public let message: String?

    public init(_ code: Code, message: String? = nil) {
        self.code = code
        self.message = message
    }
}
