import UIKit
import WebKit
import AVFoundation
import PhotosUI

final class ViewController: UIViewController,
                            WKNavigationDelegate,
                            WKUIDelegate,
                            WKScriptMessageHandler,
                            AVSpeechSynthesizerDelegate {

    // MARK: - Shared Process Pool
    //
    // Physical iOS devices are known to sometimes fail to sync a
    // freshly-set session cookie into WKHTTPCookieStore in time for
    // the very next request (WebKit bug 177478 and related reports).
    // Never recreating the process pool is one of the standard
    // mitigations, so it's a static, app-lifetime constant rather
    // than a fresh WKProcessPool() built inside setupWebView().
    private static let sharedProcessPool = WKProcessPool()


    // MARK: - WebView

    private var webView: WKWebView!


    // MARK: - Speech

    private var speechSynthesizer: AVSpeechSynthesizer?
    private var currentMessageId: String?


    // MARK: - Splash

    private var splashContainer: UIView!
    private var splashImageView: UIImageView!
    private var loadingLabel: UILabel!
    private var activityIndicator: UIActivityIndicatorView!

    private var pageLoaded = false
    private var splashMinTimePassed = false

    private let splashMinTime: TimeInterval = 2.0


    // MARK: - File Upload

    private var fileUploadCompletion: (([URL]?) -> Void)?


    // MARK: - Cookie Sync Workaround (physical device login bug)
    //
    // On real hardware, a session cookie set by a POST response (e.g.
    // a login form submit) is sometimes not committed into
    // WKHTTPCookieStore in time for the page that follows, so the
    // server sees an anonymous session and the "after login" redirect
    // silently doesn't happen. It only ever shows up after the app is
    // relaunched, because by then the cookie has finally been written
    // to the persistent store. This does not happen in Safari, the
    // Simulator, or Android WebView, because none of them share this
    // specific WKWebView-embedded timing bug.
    //
    // We track POST navigations and, once, give the cookie store a
    // moment to catch up and retry.
    private var isPostSubmissionInFlight = false
    private var hasRetriedPostSync = false


    // MARK: - Website

    private let websiteURL = "https://apnaconnect.com.au"


    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .white

        setupSpeech()
        setupSplashUI()
        setupWebView()
        setupBackNavigation()

        DispatchQueue.main.asyncAfter(deadline: .now() + splashMinTime) {
            [weak self] in

            guard let self = self else {
                return
            }

            self.splashMinTimePassed = true
            self.maybeHideSplash()
        }
    }


    deinit {

        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "xhrCookieSync")
        webView?.configuration.userContentController.removeScriptMessageHandler(
            forName: "shareText"
        )

        webView?.configuration.userContentController.removeScriptMessageHandler(
            forName: "getAuthToken"
        )

        webView?.configuration.userContentController.removeScriptMessageHandler(
            forName: "speakText"
        )

        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil

        speechSynthesizer?.stopSpeaking(
            at: .immediate
        )
    }


    // MARK: - Speech

    private func setupSpeech() {

        speechSynthesizer = AVSpeechSynthesizer()
        speechSynthesizer?.delegate = self
    }


    // MARK: - Splash

    private func setupSplashUI() {

        splashContainer = UIView()
        splashContainer.translatesAutoresizingMaskIntoConstraints = false
        splashContainer.backgroundColor = .black

        view.addSubview(splashContainer)

        NSLayoutConstraint.activate([
            splashContainer.leadingAnchor.constraint(
                equalTo: view.leadingAnchor
            ),

            splashContainer.trailingAnchor.constraint(
                equalTo: view.trailingAnchor
            ),

            splashContainer.topAnchor.constraint(
                equalTo: view.topAnchor
            ),

            splashContainer.bottomAnchor.constraint(
                equalTo: view.bottomAnchor
            )
        ])


        // Full splash artwork.
        //
        // Assets.xcassets
        //     splashScreen.imageset
        //
        // splashScreen.png

        splashImageView = UIImageView()
        splashImageView.translatesAutoresizingMaskIntoConstraints = false

        splashImageView.image =
            UIImage(named: "splashScreen")

        splashImageView.contentMode = .scaleAspectFill
        splashImageView.clipsToBounds = true

        splashContainer.addSubview(
            splashImageView
        )

        NSLayoutConstraint.activate([
            splashImageView.leadingAnchor.constraint(
                equalTo: splashContainer.leadingAnchor
            ),

            splashImageView.trailingAnchor.constraint(
                equalTo: splashContainer.trailingAnchor
            ),

            splashImageView.topAnchor.constraint(
                equalTo: splashContainer.topAnchor
            ),

            splashImageView.bottomAnchor.constraint(
                equalTo: splashContainer.bottomAnchor
            )
        ])


        // Native loading indicator

        if #available(iOS 13.0, *) {
            activityIndicator =
                UIActivityIndicatorView(
                    style: .medium
                )
        } else {
            activityIndicator =
                UIActivityIndicatorView(
                    style: .white
                )
        }

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.color = .white
        activityIndicator.hidesWhenStopped = false
        activityIndicator.startAnimating()

        splashContainer.addSubview(
            activityIndicator
        )


        // Loading text

        loadingLabel = UILabel()
        loadingLabel.translatesAutoresizingMaskIntoConstraints = false

        loadingLabel.text = "Loading..."
        loadingLabel.textColor = .white
        loadingLabel.font =
            UIFont.systemFont(
                ofSize: 15,
                weight: .medium
            )

        loadingLabel.textAlignment = .center

        splashContainer.addSubview(
            loadingLabel
        )


        NSLayoutConstraint.activate([

            activityIndicator.centerXAnchor.constraint(
                equalTo: splashContainer.centerXAnchor
            ),

            activityIndicator.bottomAnchor.constraint(
                equalTo: loadingLabel.topAnchor,
                constant: -10
            ),

            loadingLabel.centerXAnchor.constraint(
                equalTo: splashContainer.centerXAnchor
            ),

            loadingLabel.bottomAnchor.constraint(
                equalTo: splashContainer.safeAreaLayoutGuide.bottomAnchor,
                constant: -60
            )
        ])
    }


    private func maybeHideSplash() {

        guard pageLoaded,
              splashMinTimePassed
        else {
            return
        }


        UIView.animate(
            withDuration: 0.5,
            delay: 0,
            options: [.curveEaseOut],
            animations: {
                self.splashContainer.alpha = 0
            },
            completion: { _ in

                self.activityIndicator.stopAnimating()

                self.splashContainer.isHidden = true

                self.splashContainer.removeFromSuperview()
            }
        )
    }


    // MARK: - WebView Setup


    private func setupWebView() {

        let configuration = WKWebViewConfiguration()

        // ---------------------------------------------------------
        // Persistent Process Pool & Website Storage
        // Ensures PHP PHPSESSID cookies persist across HTTP redirects
        // ---------------------------------------------------------

        configuration.processPool = ViewController.sharedProcessPool

        // Persistent website storage for login/session cookies
        configuration.websiteDataStore = WKWebsiteDataStore.default()

        // Enable automatic JS window opens for post-XHR redirects
        let preferences = WKPreferences()
        preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.preferences = preferences


        // ---------------------------------------------------------
        // JavaScript bridge & XHR Cookie Interceptor
        // ---------------------------------------------------------

        let userContentController = WKUserContentController()

        // XHR/Fetch Interceptor JS: Flushes document cookies across IPC bridge on AJAX complete
        let xhrCookieFixJS = """
        (function() {
            var origOpen = XMLHttpRequest.prototype.open;
            var origSend = XMLHttpRequest.prototype.send;

            XMLHttpRequest.prototype.open = function() {
                this._url = arguments[1];
                return origOpen.apply(this, arguments);
            };

            XMLHttpRequest.prototype.send = function() {
                var self = this;
                this.addEventListener('readystatechange', function() {
                    if (self.readyState === 4) {
                        try {
                            window.webkit.messageHandlers.xhrCookieSync.postMessage({
                                url: self._url,
                                cookies: document.cookie
                            });
                        } catch(e) {}
                    }
                }, false);
                return origSend.apply(this, arguments);
            };

            if (window.fetch) {
                var origFetch = window.fetch;
                window.fetch = function() {
                    return origFetch.apply(this, arguments).then(function(response) {
                        try {
                            window.webkit.messageHandlers.xhrCookieSync.postMessage({
                                url: response.url,
                                cookies: document.cookie
                            });
                        } catch(e) {}
                        return response;
                    });
                };
            }
        })();
        """

        let userScript = WKUserScript(
            source: xhrCookieFixJS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )

        userContentController.addUserScript(userScript)

        // Handlers
        userContentController.add(self, name: "xhrCookieSync")
        userContentController.add(self, name: "shareText")
        userContentController.add(self, name: "getAuthToken")
        userContentController.add(self, name: "speakText")

        configuration.userContentController = userContentController


        // ---------------------------------------------------------
        // Inline media
        // ---------------------------------------------------------

        configuration.allowsInlineMediaPlayback = true

        if #available(iOS 10.0, *) {
            configuration.mediaTypesRequiringUserActionForPlayback = []
        }


        // ---------------------------------------------------------
        // Create WebView
        // ---------------------------------------------------------

        webView = WKWebView(
            frame: .zero,
            configuration: configuration
        )

        webView.translatesAutoresizingMaskIntoConstraints = false

        webView.navigationDelegate = self
        webView.uiDelegate = self

        webView.backgroundColor = .white
        webView.isOpaque = true


        // WebView goes below splash.

        view.insertSubview(
            webView,
            at: 0
        )


        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(
                equalTo: view.leadingAnchor
            ),
            webView.trailingAnchor.constraint(
                equalTo: view.trailingAnchor
            ),
            webView.topAnchor.constraint(
                equalTo: view.topAnchor
            ),
            webView.bottomAnchor.constraint(
                equalTo: view.bottomAnchor
            )
        ])


        loadWebsite()
    }


    // MARK: - Load Website

    private func loadWebsite() {

        guard let url =
            URL(string: websiteURL)
        else {

            print("❌ Invalid website URL")

            return
        }


        print("🌐 Loading:")
        print(url.absoluteString)


        var request =
            URLRequest(
                url: url
            )

        request.cachePolicy =
            .useProtocolCachePolicy

        request.timeoutInterval = 60


        webView.load(
            request
        )
    }


    // MARK: - Back Navigation

    private func setupBackNavigation() {

        let backGesture =
            UIScreenEdgePanGestureRecognizer(
                target: self,
                action: #selector(handleBackGesture(_:))
            )

        backGesture.edges = .left

        view.addGestureRecognizer(
            backGesture
        )
    }


    @objc private func handleBackGesture(
        _ gesture: UIScreenEdgePanGestureRecognizer
    ) {

        guard gesture.state == .ended else {
            return
        }


        if webView.canGoBack {

            webView.goBack()
        }
    }


    // MARK: - Navigation Action

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {

        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        let isMainFrame =
            navigationAction.targetFrame?.isMainFrame ?? true

        let isUserNavigation =
            navigationAction.navigationType == .linkActivated

        print("")
        print("➡️ NAVIGATION REQUEST")
        print("URL: \(url.absoluteString)")
        print("Scheme: \(url.scheme ?? "nil")")
        print("Host: \(url.host ?? "nil")")
        print("Navigation type: \(navigationAction.navigationType.rawValue)")
        print("Main frame: \(isMainFrame)")
        print("User navigation: \(isUserNavigation)")
        print("")


        // ---------------------------------------------------------
        // Never intercept sub-frame navigation.
        //
        // This is important for embedded Instagram/Facebook/etc.
        // content. An embedded post can load its own URLs without
        // taking the user out of Apna Connect.
        // ---------------------------------------------------------

        if !isMainFrame {
            decisionHandler(.allow)
            return
        }


        // ---------------------------------------------------------
        // Telephone
        // ---------------------------------------------------------

        if url.scheme?.lowercased() == "tel" {

            openExternalURL(url)

            decisionHandler(.cancel)
            return
        }


        // ---------------------------------------------------------
        // Email
        // ---------------------------------------------------------

        if url.scheme?.lowercased() == "mailto" {

            openExternalURL(url)

            decisionHandler(.cancel)
            return
        }


        // ---------------------------------------------------------
        // SMS
        // ---------------------------------------------------------

        if url.scheme?.lowercased() == "sms" {

            openExternalURL(url)

            decisionHandler(.cancel)
            return
        }


        // ---------------------------------------------------------
        // IMPORTANT:
        //
        // Only route HTTPS links for external apps when the user
        // actually clicked/activated the link.
        //
        // Automatic redirects, iframe/embed navigation, page loads,
        // JavaScript navigation, login redirects, etc. remain inside
        // WKWebView.
        // ---------------------------------------------------------

        if isUserNavigation {

            // Google Maps

            if isGoogleMapsURL(url) {

                print("🗺️ User clicked Google Maps")

                openGoogleMaps(url)

                decisionHandler(.cancel)
                return
            }


            // WhatsApp

            if isWhatsAppURL(url) {

                print("💬 User clicked WhatsApp")

                openWhatsApp(url)

                decisionHandler(.cancel)
                return
            }


            // Instagram

            if isInstagramURL(url) {

                print("📸 User clicked Instagram")

                openInstagram(url)

                decisionHandler(.cancel)
                return
            }


            // Facebook

            if isFacebookURL(url) {

                print("📘 User clicked Facebook")

                openFacebook(url)

                decisionHandler(.cancel)
                return
            }


            // X / Twitter

            if isTwitterURL(url) {

                print("𝕏 User clicked X/Twitter")

                openTwitter(url)

                decisionHandler(.cancel)
                return
            }


            // LinkedIn

            if isLinkedInURL(url) {

                print("💼 User clicked LinkedIn")

                openLinkedIn(url)

                decisionHandler(.cancel)
                return
            }


            // Spotify

            if isSpotifyURL(url) {

                print("🎵 User clicked Spotify")

                openSpotify(url)

                decisionHandler(.cancel)
                return
            }


            // Telegram

            if isTelegramURL(url) {

                print("✈️ User clicked Telegram")

                openTelegram(url)

                decisionHandler(.cancel)
                return
            }


            // Pinterest

            if isPinterestURL(url) {

                print("📌 User clicked Pinterest")

                openPinterest(url)

                decisionHandler(.cancel)
                return
            }
        }


        // ---------------------------------------------------------
        // Normal HTTP / HTTPS
        //
        // This includes:
        //
        // - Apna Connect navigation
        // - login redirects
        // - dashboard redirects
        // - authentication callbacks
        // - embedded web content
        // - automatic redirects
        // ---------------------------------------------------------

        if let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {

            if navigationAction.request.httpMethod == "POST" {

                print("📝 POST navigation detected (likely a form submit, e.g. login)")

                isPostSubmissionInFlight = true
                hasRetriedPostSync = false
            }

            decisionHandler(.allow)
            return
        }


        // ---------------------------------------------------------
        // Other custom URL schemes
        // ---------------------------------------------------------

        if let scheme = url.scheme?.lowercased(),
           !scheme.isEmpty,
           UIApplication.shared.canOpenURL(url) {

            openExternalURL(url)

            decisionHandler(.cancel)
            return
        }

        

        decisionHandler(.allow)
    }


    // MARK: - target="_blank"

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {

        guard let url =
            navigationAction.request.url
        else {
            return nil
        }


        let isUserNavigation =
            navigationAction.navigationType == .linkActivated

        print("🔗 NEW WINDOW:")
        print(url.absoluteString)
        print("User navigation:", isUserNavigation)


        // Only route external application links when the user
        // actually activated the link.

        if isUserNavigation {

            if isGoogleMapsURL(url) {

                openGoogleMaps(url)
                return nil
            }


            if isWhatsAppURL(url) {

                openWhatsApp(url)
                return nil
            }


            if isInstagramURL(url) {

                openInstagram(url)
                return nil
            }


            if isFacebookURL(url) {

                openFacebook(url)
                return nil
            }


            if isTwitterURL(url) {

                openTwitter(url)
                return nil
            }


            if isLinkedInURL(url) {

                openLinkedIn(url)
                return nil
            }


            if isSpotifyURL(url) {

                openSpotify(url)
                return nil
            }


            if isTelegramURL(url) {

                openTelegram(url)
                return nil
            }


            if isPinterestURL(url) {

                openPinterest(url)
                return nil
            }
        }


        // Normal web content stays inside the current WebView.

        webView.load(
            URLRequest(url: url)
        )

        return nil
    }


    // MARK: - Navigation Started

    func webView(
        _ webView: WKWebView,
        didStartProvisionalNavigation navigation: WKNavigation!
    ) {

        print("🌐 Navigation STARTED:")
        print(
            webView.url?.absoluteString
            ?? "unknown"
        )
    }


    // MARK: - Navigation Finished

    func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {

        print("✅ Navigation FINISHED:")
        print(
            webView.url?.absoluteString
            ?? "unknown"
        )


        pageLoaded = true


        maybeHideSplash()


        // Login/session diagnostics.

        debugAuthenticationState()


        // ---------------------------------------------------------
        // Cookie sync retry (physical device login bug)
        //
        // If the navigation that just finished was a POST (login
        // submit), the session cookie may not have been committed to
        // WKHTTPCookieStore in time for the response we just
        // rendered. Give it a moment, nudge the store by reading it,
        // then reload ONCE so a by-then-synced cookie gets a chance
        // to be honored. hasRetriedPostSync guarantees this can only
        // fire a single time per submit, so it can't loop forever if
        // the login actually failed for a real reason (bad password,
        // etc).
        // ---------------------------------------------------------

        if isPostSubmissionInFlight && !hasRetriedPostSync {

            isPostSubmissionInFlight = false
            hasRetriedPostSync = true

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in

                guard let self = self else { return }

                self.webView.configuration
                    .websiteDataStore
                    .httpCookieStore
                    .getAllCookies { _ in

                        DispatchQueue.main.async {

                            print("🔄 Reloading once after POST to pick up newly-synced session cookie")

                            self.webView.reload()
                        }
                    }
            }
        }


        // Share bridge.

        DispatchQueue.main.asyncAfter(
            deadline: .now() + 0.5
        ) { [weak self] in

            self?.injectShareOverrides()
        }


        // Cookie diagnostics.

        webView.configuration
            .websiteDataStore
            .httpCookieStore
            .getAllCookies { cookies in

                print("")
                print("🍪 WEBVIEW COOKIES: \(cookies.count)")

                for cookie in cookies {

                    print(
                        "COOKIE:",
                        cookie.name,
                        "| domain:",
                        cookie.domain,
                        "| path:",
                        cookie.path,
                        "| secure:",
                        cookie.isSecure
                    )
                }

                print("")
            }
    }


    // MARK: - Navigation Failed

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {

        print("❌ Navigation failed:")
        print(
            webView.url?.absoluteString
            ?? "unknown"
        )

        print(
            error.localizedDescription
        )
    }


    // MARK: - Provisional Navigation Failed

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {

        print("❌ Provisional navigation failed:")

        print(
            webView.url?.absoluteString
            ?? "unknown"
        )

        print(
            error.localizedDescription
        )
    }


    // MARK: - WebContent Process Terminated
    //
    // Another real-device-only WKWebView failure mode: the WebContent
    // process can be killed by the OS (memory pressure, etc.) without
    // any error being reported to the delegate, leaving the page
    // frozen. Reloading recovers it instead of the app looking stuck.

    func webViewWebContentProcessDidTerminate(
        _ webView: WKWebView
    ) {

        print("⚠️ WebContent process terminated - reloading")

        webView.reload()
    }


    // MARK: - Response

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {

        let url = navigationResponse.response.url?.absoluteString ?? "unknown"
        print("🌐 RESPONSE:")
        print(url)

        if let httpResponse = navigationResponse.response as? HTTPURLResponse {
            print("HTTP STATUS:", httpResponse.statusCode)

            // ---------------------------------------------------------
            // PHP Cookie Sync Fix for Physical iOS Devices
            //
            // NOTE: since iOS 12, WebKit no longer exposes Set-Cookie
            // in the headers handed to app code for privacy reasons,
            // so `cookies` below is almost always empty on a modern
            // OS and this block rarely does anything. It's left in
            // place (harmless) with a print so you can confirm that
            // in the Xcode console - this is NOT what is causing the
            // login redirect bug; see the POST-retry logic in
            // didFinish instead.
            // ---------------------------------------------------------
            if let responseURL = httpResponse.url,
            let headerFields = httpResponse.allHeaderFields as? [String: String] {
                
                let cookies = HTTPCookie.cookies(
                    withResponseHeaderFields: headerFields,
                    for: responseURL
                )

                print("🍪 Set-Cookie headers visible to app:", cookies.count)

                for cookie in cookies {
                    webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
                }
            }
        }


        decisionHandler(.allow)
    }


    // MARK: - Authentication Diagnostics

    private func debugAuthenticationState() {

        let js = """
        (function() {

            var local = {};

            try {
                for (var i = 0; i < localStorage.length; i++) {
                    var key = localStorage.key(i);

                    if (key) {
                        local[key] = localStorage.getItem(key);
                    }
                }
            } catch (e) {}

            var session = {};

            try {
                for (var j = 0; j < sessionStorage.length; j++) {
                    var sessionKey = sessionStorage.key(j);

                    if (sessionKey) {
                        session[sessionKey] =
                            sessionStorage.getItem(sessionKey);
                    }
                }
            } catch (e) {}

            return JSON.stringify({
                url: window.location.href,
                localStorageKeys: Object.keys(local),
                sessionStorageKeys: Object.keys(session),
                localStorage: local,
                sessionStorage: session
            });

        })();
        """


        webView.evaluateJavaScript(
            js
        ) { result, error in

            if let error = error {

                print(
                    "⚠️ Storage diagnostic error:"
                )

                print(
                    error.localizedDescription
                )

                return
            }


            print("")
            print("💾 WEB STORAGE:")
            print(result ?? "nil")
            print("")
        }
    }


    // MARK: - External App Helper

    private func openApp(
        appURL: URL,
        fallbackURL: URL
    ) {

        print("📱 Native URL:")
        print(appURL.absoluteString)

        guard UIApplication.shared.canOpenURL(appURL) else {

            print("⚠️ Native app not installed")
            print("🌐 Opening browser:")
            print(fallbackURL.absoluteString)

            UIApplication.shared.open(
                fallbackURL,
                options: [:]
            )

            return
        }

        UIApplication.shared.open(
            appURL,
            options: [:]
        ) { success in

            guard success else {

                print("❌ Native app failed to open")
                print("🌐 Falling back to browser:")
                print(fallbackURL.absoluteString)

                DispatchQueue.main.async {
                    UIApplication.shared.open(
                        fallbackURL,
                        options: [:]
                    )
                }

                return
            }

            print("✅ Native app opened")
        }
    }


    // MARK: - Generic External URL

    private func openExternalURL(
        _ url: URL
    ) {

        guard UIApplication.shared.canOpenURL(
            url
        ) else {

            print(
                "⚠️ Cannot open:",
                url.absoluteString
            )

            return
        }


        UIApplication.shared.open(
            url,
            options: [:]
        )
    }


    // MARK: - Google Maps

    private func isGoogleMapsURL(
        _ url: URL
    ) -> Bool {

        guard let host =
            url.host?.lowercased()
        else {
            return false
        }


        let path =
            url.path.lowercased()


        if host == "maps.google.com" {
            return true
        }


        if host == "maps.app.goo.gl" {
            return true
        }


        if host == "goo.gl" &&
            path.hasPrefix("/maps") {

            return true
        }


        if host.hasPrefix("maps.google.") {
            return true
        }


        if host.hasPrefix("www.google.") &&
            path.hasPrefix("/maps") {

            return true
        }


        if host.hasPrefix("google.") &&
            path.hasPrefix("/maps") {

            return true
        }


        return false
    }


    private func openGoogleMaps(
        _ url: URL
    ) {

        let original =
            url.absoluteString


        guard let nativeURL =
            URL(
                string:
                    "comgooglemapsurl://" +
                    original
                        .replacingOccurrences(
                            of: "https://",
                            with: ""
                        )
                        .replacingOccurrences(
                            of: "http://",
                            with: ""
                        )
            )
        else {

            openExternalURL(url)

            return
        }


        openApp(
            appURL: nativeURL,
            fallbackURL: url
        )
    }


    // MARK: - WhatsApp

    private func isWhatsAppURL(
        _ url: URL
    ) -> Bool {

        guard let host =
            url.host?.lowercased()
        else {
            return false
        }


        return host == "wa.me" ||
               host == "api.whatsapp.com" ||
               host == "web.whatsapp.com" ||
               host == "whatsapp.com" ||
               host.hasSuffix(".whatsapp.com")
    }


    private func openWhatsApp(
        _ url: URL
    ) {

        guard var components =
            URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
            )
        else {

            openExternalURL(url)

            return
        }


        let phone =
            components.queryItems?
                .first(
                    where: {
                        $0.name.lowercased() == "phone"
                    }
                )?
                .value


        let text =
            components.queryItems?
                .first(
                    where: {
                        $0.name.lowercased() == "text"
                    }
                )?
                .value


        if phone == nil,
           url.host?.lowercased() == "wa.me" {

            let path =
                url.path
                    .trimmingCharacters(
                        in: CharacterSet(
                            charactersIn: "/"
                        )
                    )

            if !path.isEmpty {

                components.queryItems =
                    [
                        URLQueryItem(
                            name: "phone",
                            value: path
                        )
                    ]
            }
        }


        var queryItems =
            components.queryItems ?? []


        if let text = text {

            queryItems.removeAll {
                $0.name.lowercased() == "text"
            }

            queryItems.append(
                URLQueryItem(
                    name: "text",
                    value: text
                )
            )
        }


        components.queryItems =
            queryItems


        var nativeURL =
            URLComponents()

        nativeURL.scheme = "whatsapp"
        nativeURL.host = "send"
        nativeURL.queryItems =
            components.queryItems


        guard let appURL =
            nativeURL.url
        else {

            openExternalURL(url)

            return
        }


        openApp(
            appURL: appURL,
            fallbackURL: url
        )
    }


    // MARK: - Instagram

    private func isInstagramURL(
        _ url: URL
    ) -> Bool {

        guard let host =
            url.host?.lowercased()
        else {
            return false
        }


        return host == "instagram.com" ||
               host == "www.instagram.com"
    }


    private func openInstagram(
        _ url: URL
    ) {

        let path =
            url.path


        let nativeURL =
            URL(
                string:
                    "instagram://app" +
                    path
            )
            ??
            URL(
                string:
                    "instagram://app"
            )


        guard let appURL =
            nativeURL
        else {

            openExternalURL(url)

            return
        }


        openApp(
            appURL: appURL,
            fallbackURL: url
        )
    }


    // MARK: - Facebook

    private func isFacebookURL(
        _ url: URL
    ) -> Bool {

        guard let host =
            url.host?.lowercased()
        else {
            return false
        }


        return host == "facebook.com" ||
               host == "www.facebook.com" ||
               host.hasSuffix(".facebook.com")
    }


    private func openFacebook(
        _ url: URL
    ) {

        let encoded =
            url.absoluteString
                .addingPercentEncoding(
                    withAllowedCharacters:
                        .urlQueryAllowed
                )
                ?? url.absoluteString


        guard let appURL =
            URL(
                string:
                    "fb://facewebmodal/f?href=\(encoded)"
            )
        else {

            openExternalURL(url)

            return
        }


        openApp(
            appURL: appURL,
            fallbackURL: url
        )
    }


    // MARK: - X / Twitter

    private func isTwitterURL(
        _ url: URL
    ) -> Bool {

        guard let host =
            url.host?.lowercased()
        else {
            return false
        }


        return host == "twitter.com" ||
               host == "www.twitter.com" ||
               host == "x.com" ||
               host == "www.x.com"
    }


    private func openTwitter(
        _ url: URL
    ) {

        if let xURL = URL(string: "x://"),
           UIApplication.shared.canOpenURL(xURL) {

            openApp(
                appURL: xURL,
                fallbackURL: url
            )

            return
        }

        if let twitterURL = URL(string: "twitter://"),
           UIApplication.shared.canOpenURL(twitterURL) {

            openApp(
                appURL: twitterURL,
                fallbackURL: url
            )

            return
        }

        openExternalURL(url)
    }


    // MARK: - LinkedIn

    private func isLinkedInURL(
        _ url: URL
    ) -> Bool {

        guard let host =
            url.host?.lowercased()
        else {
            return false
        }


        return host == "linkedin.com" ||
               host == "www.linkedin.com" ||
               host.hasSuffix(".linkedin.com")
    }


    private func openLinkedIn(
        _ url: URL
    ) {

        guard let appURL =
            URL(
                string:
                    "linkedin://"
            )
        else {

            openExternalURL(url)

            return
        }


        openApp(
            appURL: appURL,
            fallbackURL: url
        )
    }


    // MARK: - Spotify

    private func isSpotifyURL(
        _ url: URL
    ) -> Bool {

        guard let host =
            url.host?.lowercased()
        else {
            return false
        }


        return host == "open.spotify.com" ||
               host == "spotify.com" ||
               host == "www.spotify.com"
    }


    private func openSpotify(
        _ url: URL
    ) {

        var nativeString =
            "spotify:" +
            url.path


        if let query =
            url.query,
           !query.isEmpty {

            nativeString += "?" + query
        }


        guard let appURL =
            URL(
                string:
                    nativeString
            )
        else {

            openExternalURL(url)

            return
        }


        openApp(
            appURL: appURL,
            fallbackURL: url
        )
    }


    // MARK: - Telegram

    private func isTelegramURL(
        _ url: URL
    ) -> Bool {

        guard let host =
            url.host?.lowercased()
        else {
            return false
        }


        return host == "t.me" ||
               host == "telegram.me" ||
               host == "telegram.dog"
    }


    private func openTelegram(
        _ url: URL
    ) {

        let path =
            url.path
                .trimmingCharacters(
                    in: CharacterSet(
                        charactersIn: "/"
                    )
                )


        if !path.isEmpty {

            let encoded =
                path.addingPercentEncoding(
                    withAllowedCharacters:
                        .urlPathAllowed
                )
                ?? path


            if let appURL =
                URL(
                    string:
                        "tg://resolve?domain=\(encoded)"
                ) {

                if UIApplication.shared.canOpenURL(
                    appURL
                ) {

                    UIApplication.shared.open(
                        appURL,
                        options: [:]
                    )

                    return
                }
            }
        }


        guard let appURL =
            URL(
                string:
                    "tg://"
            )
        else {

            openExternalURL(url)

            return
        }


        openApp(
            appURL: appURL,
            fallbackURL: url
        )
    }


    // MARK: - Pinterest

    private func isPinterestURL(
        _ url: URL
    ) -> Bool {

        guard let host =
            url.host?.lowercased()
        else {
            return false
        }


        return host == "pinterest.com" ||
               host == "www.pinterest.com" ||
               host == "pin.it"
    }


    private func openPinterest(
        _ url: URL
    ) {

        guard let appURL =
            URL(
                string:
                    "pinterest://"
            )
        else {

            openExternalURL(url)

            return
        }


        openApp(
            appURL: appURL,
            fallbackURL: url
        )
    }


    // MARK: - Share JavaScript

    private func injectShareOverrides() {

        let js = """
        (function() {

            if (
                typeof window.webkit === 'undefined' ||
                typeof window.webkit.messageHandlers === 'undefined'
            ) {
                return;
            }

            console.log('🔧 iOS Share interceptor active');


            function getPostUrlFromId(postId) {

                if (
                    window.location.pathname.includes('/post/') ||
                    window.location.search.includes('link1=post')
                ) {
                    return window.location.href;
                }


                return window.location.origin +
                       '/index.php?link1=post&id=' +
                       postId;
            }


            if (window.SharePostRTE) {

                window.SharePostRTE.show = function() {

                    var postId = null;

                    var postElem =
                        document.querySelector('[data-post-id]');


                    if (postElem) {

                        postId =
                            postElem.getAttribute(
                                'data-post-id'
                            );
                    }


                    window.webkit.messageHandlers.shareText.postMessage(
                        getPostUrlFromId(postId)
                    );


                    return false;
                };


                window.SharePostRTE.open = function() {

                    window.SharePostRTE.show();

                    return false;
                };
            }


            document.body.addEventListener(
                'click',
                function(e) {

                    var target =
                        e.target.closest(
                            '.stat-item, .btn, [onclick*="Share"], [title*="share"]'
                        );


                    if (!target) {
                        return;
                    }


                    var isShareBtn = false;


                    if (
                        target.getAttribute('title') &&
                        target.getAttribute('title')
                            .toLowerCase()
                            .includes('share')
                    ) {

                        isShareBtn = true;
                    }


                    if (
                        target.innerHTML &&
                        target.innerHTML
                            .toLowerCase()
                            .includes('share')
                    ) {

                        isShareBtn = true;
                    }


                    if (
                        target.onclick &&
                        target.onclick
                            .toString()
                            .includes('Share')
                    ) {

                        isShareBtn = true;
                    }


                    if (!isShareBtn) {
                        return;
                    }


                    e.preventDefault();
                    e.stopPropagation();
                    e.stopImmediatePropagation();


                    var postContainer =
                        target.closest(
                            '[data-post-id]'
                        );


                    var postId =
                        postContainer
                            ? postContainer.getAttribute(
                                'data-post-id'
                              )
                            : null;


                    window.webkit.messageHandlers.shareText.postMessage(
                        getPostUrlFromId(postId)
                    );

                },
                true
            );


        })();
        """


        webView.evaluateJavaScript(
            js
        ) { _, error in

            if let error = error {

                print(
                    "⚠️ Share JS injection error:"
                )

                print(
                    error.localizedDescription
                )

            } else {

                print(
                    "✅ Share interceptor installed"
                )
            }
        }
    }


    // MARK: - TTS -> JavaScript

    private func sendToJs(
        event: String,
        messageId: String
    ) {

        let escapedEvent =
            event
                .replacingOccurrences(
                    of: "\\",
                    with: "\\\\"
                )
                .replacingOccurrences(
                    of: "'",
                    with: "\\'"
                )


        let escapedMessageId =
            messageId
                .replacingOccurrences(
                    of: "\\",
                    with: "\\\\"
                )
                .replacingOccurrences(
                    of: "'",
                    with: "\\'"
                )


        let script = """
        window.dispatchEvent(
            new CustomEvent(
                'AndroidTTSEvent',
                {
                    detail: {
                        event: '\(escapedEvent)',
                        messageId: '\(escapedMessageId)'
                    }
                }
            )
        );
        """


        webView.evaluateJavaScript(
            script,
            completionHandler: nil
        )
    }


    // MARK: - Speech Delegate

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {

        if let messageId =
            currentMessageId {

            sendToJs(
                event: "onSpeechStart",
                messageId: messageId
            )
        }
    }


    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {

        if let messageId =
            currentMessageId {

            sendToJs(
                event: "onSpeechEnd",
                messageId: messageId
            )
        }


        currentMessageId = nil
    }


    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {

        if let messageId =
            currentMessageId {

            sendToJs(
                event: "onSpeechEnd",
                messageId: messageId
            )
        }


        currentMessageId = nil
    }
}


// MARK: - WKScriptMessageHandler

extension ViewController {

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {

        guard let body =
            message.body as? String
        else {
            return
        }


        switch message.name {


        // ---------------------------------------------------------
        // XHR Cookie Sync (NEW CASE FOR PHYSICAL IPHONE FIX)
        // ---------------------------------------------------------

        case "xhrCookieSync":

            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self = self else { return }
                for cookie in cookies {
                    self.webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
                }
            }


        // ---------------------------------------------------------
        // Share
        // ---------------------------------------------------------

        case "shareText":

            let activityVC =
                UIActivityViewController(
                    activityItems: [body],
                    applicationActivities: nil
                )


            if let popover =
                activityVC.popoverPresentationController {

                popover.sourceView =
                    view

                popover.sourceRect =
                    CGRect(
                        x: view.bounds.midX,
                        y: view.bounds.midY,
                        width: 0,
                        height: 0
                    )

                popover.permittedArrowDirections = []
            }


            present(
                activityVC,
                animated: true
            )


        // ---------------------------------------------------------
        // Auth token
        //
        // Same behavior as Android:
        // receive/log the token.
        // We do NOT manually redirect here.
        // ---------------------------------------------------------

        case "getAuthToken":

            print("")
            print("🔑 DEVICE AUTH TOKEN RECEIVED")
            print(body)
            print("")


        // ---------------------------------------------------------
        // TTS
        // ---------------------------------------------------------

        case "speakText":

            guard let synthesizer =
                speechSynthesizer
            else {
                return
            }


            if synthesizer.isSpeaking {

                synthesizer.stopSpeaking(
                    at: .immediate
                )


                if let messageId =
                    currentMessageId {

                    sendToJs(
                        event: "onSpeechEnd",
                        messageId: messageId
                    )
                }


                currentMessageId = nil

                return
            }


            currentMessageId =
                "ttsMessageId"


            let utterance =
                AVSpeechUtterance(
                    string: body
                )


            utterance.voice =
                AVSpeechSynthesisVoice(
                    language: "en-US"
                )


            synthesizer.speak(
                utterance
            )


        default:

            print(
                "⚠️ Unknown JavaScript message:",
                message.name
            )
        }
    }
}


// MARK: - WKUIDelegate
// Camera / Microphone / File Upload

extension ViewController {

    @available(iOS 15.0, *)
    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {

        print("")
        print("🎤📷 MEDIA PERMISSION REQUEST")
        print("Host:", origin.host)
        print("Type:", type.rawValue)
        print("")


        switch type {

        case .camera:

            AVCaptureDevice.requestAccess(
                for: .video
            ) { granted in

                DispatchQueue.main.async {

                    decisionHandler(
                        granted
                        ? .grant
                        : .deny
                    )
                }
            }


        case .microphone:

            AVCaptureDevice.requestAccess(
                for: .audio
            ) { granted in

                DispatchQueue.main.async {

                    decisionHandler(
                        granted
                        ? .grant
                        : .deny
                    )
                }
            }


        case .cameraAndMicrophone:

            let group =
                DispatchGroup()

            var cameraGranted = false
            var microphoneGranted = false


            group.enter()

            AVCaptureDevice.requestAccess(
                for: .video
            ) { granted in

                cameraGranted = granted

                group.leave()
            }


            group.enter()

            AVCaptureDevice.requestAccess(
                for: .audio
            ) { granted in

                microphoneGranted = granted

                group.leave()
            }


            group.notify(
                queue: .main
            ) {

                decisionHandler(
                    cameraGranted &&
                    microphoneGranted
                    ? .grant
                    : .deny
                )
            }


        @unknown default:

            decisionHandler(
                .deny
            )
        }
    }


    @available(iOS 18.4, *)
    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping ([URL]?) -> Void
    ) {

        print("📁 File upload requested")


        fileUploadCompletion =
            completionHandler


        var configuration =
            PHPickerConfiguration()

        configuration.selectionLimit =
            parameters.allowsMultipleSelection
            ? 0
            : 1

        configuration.filter =
            .any(of: [
                .images,
                .videos
            ])


        let picker =
            PHPickerViewController(
                configuration:
                    configuration
            )


        picker.delegate = self


        present(
            picker,
            animated: true
        )
    }
}


// MARK: - PHPicker Delegate

extension ViewController: PHPickerViewControllerDelegate {

    func picker(
        _ picker: PHPickerViewController,
        didFinishPicking results: [PHPickerResult]
    ) {

        picker.dismiss(
            animated: true
        )


        guard !results.isEmpty else {

            fileUploadCompletion?(
                nil
            )

            fileUploadCompletion =
                nil

            return
        }


        let dispatchGroup =
            DispatchGroup()

        var urls: [URL] = []


        for result in results {

            let provider =
                result.itemProvider


            if provider.hasItemConformingToTypeIdentifier(
                "public.image"
            ) {

                dispatchGroup.enter()


                provider.loadFileRepresentation(
                    forTypeIdentifier:
                        "public.image"
                ) { url, _ in

                    defer {
                        dispatchGroup.leave()
                    }


                    guard let url =
                        url
                    else {
                        return
                    }


                    let temporaryURL =
                        FileManager.default
                            .temporaryDirectory
                            .appendingPathComponent(
                                UUID().uuidString
                                + "-"
                                + url.lastPathComponent
                            )


                    do {

                        try FileManager.default.copyItem(
                            at: url,
                            to: temporaryURL
                        )


                        urls.append(
                            temporaryURL
                        )

                    } catch {

                        print(
                            "❌ File copy failed:",
                            error.localizedDescription
                        )
                    }
                }


            } else if provider.hasItemConformingToTypeIdentifier(
                "public.movie"
            ) {

                dispatchGroup.enter()


                provider.loadFileRepresentation(
                    forTypeIdentifier:
                        "public.movie"
                ) { url, _ in

                    defer {
                        dispatchGroup.leave()
                    }


                    guard let url =
                        url
                    else {
                        return
                    }


                    let temporaryURL =
                        FileManager.default
                            .temporaryDirectory
                            .appendingPathComponent(
                                UUID().uuidString
                                + "-"
                                + url.lastPathComponent
                            )


                    do {

                        try FileManager.default.copyItem(
                            at: url,
                            to: temporaryURL
                        )


                        urls.append(
                            temporaryURL
                        )

                    } catch {

                        print(
                            "❌ Video copy failed:",
                            error.localizedDescription
                        )
                    }
                }
            }
        }


        dispatchGroup.notify(
            queue: .main
        ) {

            self.fileUploadCompletion?(
                urls
            )

            self.fileUploadCompletion =
                nil
        }
    }
}