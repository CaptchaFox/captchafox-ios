import CaptchaFox
import SwiftUI

/// Shows the widget with the public test keys, one that always passes and one that always fails the challenge, or with
/// a site key and domain of your own.
struct ContentView: View {
    private enum Key: String, CaseIterable, Identifiable {
        case passes = "sk_11111111000000001111111100000000"
        case fails = "sk_FFFFFFFF00000000FFFFFFFF00000000"
        case custom

        var id: String { rawValue }

        var label: String {
            switch self {
            case .passes: "Passes"
            case .fails: "Fails"
            case .custom: "Custom"
            }
        }
    }

    private static let testDomain = URL(string: "https://example.com")!

    @State private var key = Key.passes
    @State private var showsModal = false
    @State private var result = "No result yet"
    // The widget's events, each with the seconds since the last load or Verify.
    @State private var events: [String] = []
    @State private var start = Date()

    // The custom site key and domain as typed, and as last applied; the widget reloads only on Use.
    @AppStorage("customSiteKey") private var customSiteKey = ""
    @AppStorage("customDomain") private var customDomain = ""
    @State private var appliedSiteKey = ""
    @State private var appliedDomain = testDomain

    private func configuration(mode: CaptchaFoxConfiguration.Mode) -> CaptchaFoxConfiguration {
        switch key {
        case .passes, .fails:
            CaptchaFoxConfiguration(siteKey: key.rawValue, baseURL: Self.testDomain, mode: mode)
        case .custom:
            CaptchaFoxConfiguration(siteKey: appliedSiteKey, baseURL: appliedDomain, mode: mode)
        }
    }

    /// `example.com` and `https://example.com` both become `https://example.com`.
    private static func url(domain: String) -> URL? {
        let trimmed = domain.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return nil
        }

        let url = URL(string: trimmed.contains("://") ? trimmed : "https://\(trimmed)")
        return url?.host == nil ? nil : url
    }

    private var canApply: Bool {
        !customSiteKey.trimmingCharacters(in: .whitespaces).isEmpty && Self.url(domain: customDomain) != nil
    }

    private func apply() {
        guard let domain = Self.url(domain: customDomain) else {
            return
        }

        appliedSiteKey = customSiteKey.trimmingCharacters(in: .whitespaces)
        appliedDomain = domain
        result = "No result yet"
        events = []
    }

    private func log(_ event: String) {
        events.append(String(format: "+%.2fs  %@", Date().timeIntervalSince(start), event))
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Site key") {
                    Picker("Site key", selection: $key) {
                        ForEach(Key.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if key == .custom {
                        TextField("Site key, sk_…", text: $customSiteKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("Domain of the site, such as example.com", text: $customDomain)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Use", action: apply)
                            .disabled(!canApply)
                    }
                }

                if key != .custom || !appliedSiteKey.isEmpty {
                    Section("Modal, hidden mode") {
                        Button("Verify") {
                            start = Date()
                            events = []
                            showsModal = true
                        }
                    }

                    Section("Inline") {
                        CaptchaFoxView(
                            configuration: configuration(mode: .inline),
                            onLoad: { start = Date(); events = []; log("load") },
                            onVerify: { result = "Token: \($0)"; log("verify") },
                            onError: { result = "Error: \($0)"; log("error: \($0)") },
                            onFail: { log("fail") },
                            onExpire: { log("expire") },
                            onClose: { log("close") },
                            onChallengeOpen: { log("challenge open") }
                        )
                        .frame(height: 80)
                    }
                }

                Section("Result") {
                    Text(result)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                }

                if !events.isEmpty {
                    Section("Events") {
                        ForEach(Array(events.enumerated()), id: \.offset) { Text($0.element).font(.footnote.monospaced()) }
                    }
                }
            }
            .navigationTitle("CaptchaFox")
        }
        .navigationViewStyle(.stack)
        .onAppear {
            if canApply {
                apply()
            }
        }
        .captchaFoxModal(
            isPresented: $showsModal,
            configuration: configuration(mode: .hidden),
            onLoad: { log("load") },
            onVerify: { result = "Token: \($0)"; log("verify") },
            onError: { result = "Error: \($0)"; log("error: \($0)") },
            onFail: { log("fail") },
            onExpire: { log("expire") },
            onClose: { result = "Closed"; log("close") },
            onChallengeOpen: { log("challenge open") }
        )
        .onChange(of: showsModal) { isShown in
            if !isShown {
                log("modal dismissed")
            }
        }
    }
}
