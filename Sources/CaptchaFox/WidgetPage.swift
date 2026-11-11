import Foundation

/// The HTML page that renders the widget and reports its callbacks to the bridge.
enum WidgetPage {
    static let scriptURL = URL(string: "https://cdn.captchafox.com/api.js?render=explicit&onload=captchafoxOnLoad")!
    static let messageHandlerName = "captchafox"

    static func html(configuration: CaptchaFoxConfiguration, scriptURL: URL) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <style>
        html, body { margin: 0; height: 100%; background: transparent; }
        body { display: flex; align-items: center; justify-content: center; }
        </style>
        <script type="application/json" id="captchafox-options">\(optionsJSON(configuration))</script>
        <script>
        (function () {
          var handler = window.webkit.messageHandlers.\(messageHandlerName);
          function post(message) { handler.postMessage(message); }
          function messageOf(error) {
            return error && typeof error.message === 'string' ? error.message : String(error || 'Unknown error');
          }
          function postError(error) { post({ type: 'error', message: messageOf(error) }); }
          window.captchafoxOnLoad = function () {
            try {
              var options = JSON.parse(document.getElementById('captchafox-options').textContent);
              options.onVerify = function (token) { post({ type: 'verify', token: token }); };
              options.onError = postError;
              options.onFail = function () { post({ type: 'fail' }); };
              options.onExpire = function () { post({ type: 'expire' }); };
              options.onClose = function () { post({ type: 'close' }); };
              options.onChallengeOpen = function () { post({ type: 'challengeOpen' }); };
              Promise.resolve(window.captchafox.render('#captchafox', options))
                .then(function () { post({ type: 'load' }); }, postError);
            } catch (error) {
              postError(error);
            }
          };
          window.captchafoxScriptFailed = function () {
            postError(new Error('The CaptchaFox script could not be loaded.'));
          };
          window.captchafoxExecute = function (id) {
            function postExecutionFailed(error) { post({ type: 'executionFailed', id: id, message: messageOf(error) }); }
            try {
              window.captchafox.execute().catch(postExecutionFailed);
            } catch (error) {
              postExecutionFailed(error);
            }
          };
          window.captchafoxReset = function () {
            try {
              window.captchafox.reset();
            } catch (error) {
              postError(error);
            }
          };
        })();
        </script>
        <script async src="\(attributeEscaped(scriptURL.absoluteString))" onerror="captchafoxScriptFailed()"></script>
        </head>
        <body><div id="captchafox"></div></body>
        </html>
        """
    }

    /// The options as a JSON data block. Values never enter script source; `<` is escaped so that no value can end the
    /// `<script>` element.
    static func optionsJSON(_ configuration: CaptchaFoxConfiguration) -> String {
        var options = ["sitekey": configuration.siteKey]
        if let mode = configuration.mode {
            options["mode"] = mode.rawValue
        }
        if let theme = configuration.theme {
            options["theme"] = theme.rawValue
        }
        if let language = configuration.language {
            options["lang"] = language
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        // Encoding a dictionary of strings cannot fail.
        let json = String(decoding: try! encoder.encode(options), as: UTF8.self)
        return json.replacingOccurrences(of: "<", with: "\\u003c")
    }

    private static func attributeEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
