/// A callback of the widget.
enum WidgetEvent: Equatable {
    case load
    case verify(token: String)
    case error(String)
    case fail
    case expire
    case close
    case challengeOpen
}

/// A message the page posts: a callback of the widget, or the rejection of the widget's `execute()` for the call with
/// the given id, which often follows the widget's own error callback and so is no event of its own.
enum PageMessage: Equatable {
    case event(WidgetEvent)
    case executionFailed(id: Int, message: String)

    /// `nil` for a message that is not one the page sends.
    init?(body: Any) {
        guard let body = body as? [String: Any], let type = body["type"] as? String else {
            return nil
        }

        switch type {
        case "load":
            self = .event(.load)
        case "verify":
            guard let token = body["token"] as? String, !token.isEmpty else {
                return nil
            }
            self = .event(.verify(token: token))
        case "error":
            self = .event(.error(Self.errorMessage(body)))
        case "fail":
            self = .event(.fail)
        case "expire":
            self = .event(.expire)
        case "close":
            self = .event(.close)
        case "challengeOpen":
            self = .event(.challengeOpen)
        case "executionFailed":
            guard let id = body["id"] as? Int else {
                return nil
            }
            self = .executionFailed(id: id, message: Self.errorMessage(body))
        default:
            return nil
        }
    }

    private static func errorMessage(_ body: [String: Any]) -> String {
        body["message"] as? String ?? "Unknown error"
    }
}
