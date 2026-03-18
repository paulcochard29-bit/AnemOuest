import SwiftUI
import WebKit

struct WindsUpLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isLoggedIn = false
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ZStack {
                WindsUpWebView(
                    isLoggedIn: $isLoggedIn,
                    isLoading: $isLoading
                )

                if isLoading {
                    ProgressView("Chargement...")
                        .padding()
                        .modifier(LiquidGlassRoundedModifier(cornerRadius: 16))
                }
            }
            .navigationTitle("Connexion WindsUp")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        dismiss()
                    }
                }
            }
            .onChange(of: isLoggedIn) { _, loggedIn in
                if loggedIn {
                    // Small delay to ensure cookies are saved
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct WindsUpWebView: UIViewRepresentable {
    @Binding var isLoggedIn: Bool
    @Binding var isLoading: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator

        // Load login page
        if let url = URL(string: "https://www.winds-up.com/index.php?p=connexion") {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WindsUpWebView
        private var cookieCheckTimer: Timer?
        private weak var webViewRef: WKWebView?

        init(_ parent: WindsUpWebView) {
            self.parent = parent
        }

        func startCookieMonitoring(webView: WKWebView) {
            self.webViewRef = webView
            // Check cookies every 2 seconds
            cookieCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                self?.checkLoginStatus()
            }
        }

        func stopCookieMonitoring() {
            cookieCheckTimer?.invalidate()
            cookieCheckTimer = nil
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = true
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
            }

            // Start monitoring cookies after first page load
            if cookieCheckTimer == nil {
                startCookieMonitoring(webView: webView)
            }

            // Also check immediately
            checkLoginStatus()
        }

        func checkLoginStatus() {
            guard let webView = webViewRef else {
                Log.debug("WindsUp WebView: No webView reference")
                return
            }

            let dataStore = webView.configuration.websiteDataStore
            dataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                // Debug: show all winds-up cookies
                let windsUpCookies = cookies.filter { $0.domain.contains("winds-up") }
                Log.debug("WindsUp WebView: Found \(windsUpCookies.count) winds-up cookies")
                for cookie in windsUpCookies {
                    Log.debug("WindsUp WebView: Cookie '\(cookie.name)' = \(cookie.value.prefix(20))...")
                }

                let hasAutolog = cookies.contains { $0.name == "autolog" }
                let hasCodeCnx = cookies.contains { $0.name == "codeCnx" }

                Log.debug("WindsUp WebView: autolog=\(hasAutolog), codeCnx=\(hasCodeCnx)")

                // autolog is the main auth cookie - codeCnx is optional
                if hasAutolog {
                    Log.debug("WindsUp WebView: Login successful! Found auth cookies")

                    // Stop monitoring
                    self?.stopCookieMonitoring()

                    // Copy cookies to shared HTTPCookieStorage for URLSession
                    for cookie in cookies {
                        if cookie.domain.contains("winds-up.com") {
                            HTTPCookieStorage.shared.setCookie(cookie)
                            Log.debug("WindsUp WebView: Copied cookie \(cookie.name)")
                        }
                    }

                    // Mark WindsUpService as authenticated
                    WindsUpService.shared.setAuthenticated(true)

                    DispatchQueue.main.async {
                        self?.parent.isLoggedIn = true
                    }
                }
            }
        }

        deinit {
            stopCookieMonitoring()
        }
    }
}
