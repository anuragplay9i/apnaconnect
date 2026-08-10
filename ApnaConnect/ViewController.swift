import UIKit
import WebKit
import AVFoundation

final class ViewController: UIViewController,
                            WKNavigationDelegate,
                            WKUIDelegate,
                            AVSpeechSynthesizerDelegate {

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

    // Minimum time that the splash remains visible.
    private let splashMinTime: TimeInterval = 1.5

    // Website
    private let websiteURL = "https://apnaconnect.com.au"


    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .white

        // 1. Speech engine
        setupSpeech()

        // 2. Splash
        setupSplashUI()

        // 3. WebView
        setupWebView()

        // 4. Minimum splash duration
        DispatchQueue.main.asyncAfter(deadline: .now() + splashMinTime) { [weak self] in
            guard let self = self else { return }

            self.splashMinTimePassed = true
            self.maybeHideSplash()
        }
    }


    // MARK: - Speech Setup

    private func setupSpeech() {
        speechSynthesizer = AVSpeechSynthesizer()
        speechSynthesizer?.delegate = self
    }


    // MARK: - Splash

    private func setupSplashUI() {

        view.backgroundColor = .white

        // Full-screen splash container
        splashContainer = UIView()
        splashContainer.translatesAutoresizingMaskIntoConstraints = false
        splashContainer.backgroundColor = .white

        view.addSubview(splashContainer)

        NSLayoutConstraint.activate([
            splashContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            splashContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            splashContainer.topAnchor.constraint(equalTo: view.topAnchor),
            splashContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])


        // ---------------------------------------------------------
        // Full splash artwork
        //
        // Add an image named "splashScreen" to Assets.xcassets.
        //
        // This should be your complete splash artwork rather than
        // just the logo.
        // ---------------------------------------------------------

        splashImageView = UIImageView()
        splashImageView.translatesAutoresizingMaskIntoConstraints = false
        splashImageView.image = UIImage(named: "splashScreen")
        splashImageView.contentMode = .scaleAspectFill
        splashImageView.clipsToBounds = true

        splashContainer.addSubview(splashImageView)

        NSLayoutConstraint.activate([
            splashImageView.leadingAnchor.constraint(equalTo: splashContainer.leadingAnchor),
            splashImageView.trailingAnchor.constraint(equalTo: splashContainer.trailingAnchor),
            splashImageView.topAnchor.constraint(equalTo: splashContainer.topAnchor),
            splashImageView.bottomAnchor.constraint(equalTo: splashContainer.bottomAnchor)
        ])


        // ---------------------------------------------------------
        // Loading label
        // ---------------------------------------------------------

        loadingLabel = UILabel()
        loadingLabel.translatesAutoresizingMaskIntoConstraints = false
        loadingLabel.text = "Loading..."
        loadingLabel.textColor = .darkGray
        loadingLabel.font = UIFont.systemFont(ofSize: 15, weight: .medium)
        loadingLabel.textAlignment = .center

        splashContainer.addSubview(loadingLabel)


        // ---------------------------------------------------------
        // Activity indicator
        // ---------------------------------------------------------

        if #available(iOS 13.0, *) {
            activityIndicator = UIActivityIndicatorView(style: .medium)
        } else {
            activityIndicator = UIActivityIndicatorView(style: .gray)
        }

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = false
        activityIndicator.startAnimating()

        splashContainer.addSubview(activityIndicator)


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


    // MARK: - Hide Splash

    private func maybeHideSplash() {

        guard pageLoaded && splashMinTimePassed else {
            return
        }

        UIView.animate(
            withDuration: 0.45,
            delay: 0,
            options: [.curveEaseOut],
            animations: { [weak self] in
                self?.splashContainer.alpha = 0
            },
            completion: { [weak self] _ in

                guard let self = self else { return }

                self.activityIndicator.stopAnimating()
                self.splashContainer.isHidden = true
                self.splashContainer.removeFromSuperview()
            }
        )
    }


    // MARK: - WebView Setup

    private func setupWebView() {

        let webConfiguration = WKWebViewConfiguration()

        let userContentController = WKUserContentController()


        // JavaScript bridge handlers

        userContentController.add(self, name: "shareText")
        userContentController.add(self, name: "getAuthToken")
        userContentController.add(self, name: "speakText")

        webConfiguration.userContentController = userContentController


        // JavaScript

        webConfiguration.preferences.javaScriptEnabled = true


        // Allow inline media

        webConfiguration.allowsInlineMediaPlayback = true

        if #available(iOS 10.0, *) {
            webConfiguration.mediaTypesRequiringUserActionForPlayback = []
        }


        // IMPORTANT:
        // Use the persistent default website data store.
        //
        // This allows WKWebView cookies/session data to persist
        // between launches, which is important for login sessions.

        webConfiguration.websiteDataStore = WKWebsiteDataStore.default()


        // Create WebView

        webView = WKWebView(
            frame: .zero,
            configuration: webConfiguration
        )

        webView.translatesAutoresizingMaskIntoConstraints = false

        webView.navigationDelegate = self
        webView.uiDelegate = self

        webView.backgroundColor = .white
        webView.isOpaque = true

        // Add WebView below splash

        view.insertSubview(webView, at: 0)

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])


        // Load website

        loadWebsite()
    }


    // MARK: - Load Website

    private func loadWebsite() {

        guard let url = URL(string: websiteURL) else {
            print("❌ Invalid website URL")
            return
        }

        print("🌐 Loading: \(url.absoluteString)")

        var request = URLRequest(url: url)

        request.cachePolicy = .useProtocolCachePolicy
        request.timeoutInterval = 60

        webView.load(request)
    }


    // MARK: - URL Routing

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {

        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        let urlString = url.absoluteString
        let scheme = url.scheme?.lowercased() ?? ""

        print("➡️ Navigation request:")
        print("   \(urlString)")


        // ---------------------------------------------------------
        // tel:
        // ---------------------------------------------------------

        if scheme == "tel" {

            openExternalURL(url)

            decisionHandler(.cancel)
            return
        }


        // ---------------------------------------------------------
        // mailto:
        // ---------------------------------------------------------

        if scheme == "mailto" {

            openExternalURL(url)

            decisionHandler(.cancel)
            return
        }


        // ---------------------------------------------------------
        // SMS
        // ---------------------------------------------------------

        if scheme == "sms" {

            openExternalURL(url)

            decisionHandler(.cancel)
            return
        }


        // ---------------------------------------------------------
        // Maps
        // ---------------------------------------------------------

        if isGoogleMapsUrl(url: url) {

            openExternalURL(url)

            decisionHandler(.cancel)
            return
        }


        // ---------------------------------------------------------
        // Social / external application URLs
        // ---------------------------------------------------------

        if isSocialOrAppUrl(urlString: urlString) {

            openExternalURL(url)

            decisionHandler(.cancel)
            return
        }


        // ---------------------------------------------------------
        // HTTP / HTTPS
        //
        // IMPORTANT:
        //
        // Keep normal HTTP/HTTPS navigation INSIDE the WebView.
        //
        // This is important for login redirects, authentication
        // callbacks, internal website routing, etc.
        // ---------------------------------------------------------

        if scheme == "http" || scheme == "https" {

            decisionHandler(.allow)
            return
        }


        // ---------------------------------------------------------
        // Unknown custom schemes
        // ---------------------------------------------------------

        if !scheme.isEmpty {

            if UIApplication.shared.canOpenURL(url) {

                openExternalURL(url)

                decisionHandler(.cancel)
                return
            }
        }


        decisionHandler(.allow)
    }


    // MARK: - Handle target="_blank"

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {

        guard let url = navigationAction.request.url else {
            return nil
        }

        print("🔗 New-window request:")
        print("   \(url.absoluteString)")


        // If the website uses target="_blank", load it in the
        // existing WebView instead of creating a blank WebView.

        webView.load(URLRequest(url: url))

        return nil
    }


    // MARK: - Navigation Started

    func webView(
        _ webView: WKWebView,
        didStartProvisionalNavigation navigation: WKNavigation!
    ) {

        print("🌐 WebView started loading:")
        print("   \(webView.url?.absoluteString ?? "unknown")")

        pageLoaded = false
    }


    // MARK: - Navigation Finished

    func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {

        print("✅ WebView finished loading:")
        print("   \(webView.url?.absoluteString ?? "unknown")")

        pageLoaded = true

        maybeHideSplash()


        // Give the page a moment to finish initializing its
        // JavaScript objects before injecting our overrides.

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.injectShareOverrides()
        }


        // Debug authentication cookies

        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies {
            cookies in

            print("🍪 WebView cookies: \(cookies.count)")

            for cookie in cookies {
                print(
                    "   \(cookie.name) | \(cookie.domain) | secure=\(cookie.isSecure)"
                )
            }
        }
    }


    // MARK: - Navigation Failed

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {

        print("❌ WebView navigation failed:")
        print("   URL: \(webView.url?.absoluteString ?? "unknown")")
        print("   Error: \(error.localizedDescription)")
    }


    // MARK: - Initial Navigation Failed

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {

        print("❌ WebView provisional navigation failed:")
        print("   URL: \(webView.url?.absoluteString ?? "unknown")")
        print("   Error: \(error.localizedDescription)")
    }


    // MARK: - Response Debugging

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {

        let url = navigationResponse.response.url?.absoluteString ?? "unknown"

        print("🌐 Response:")
        print("   URL: \(url)")


        if let httpResponse =
            navigationResponse.response as? HTTPURLResponse {

            print("   HTTP status: \(httpResponse.statusCode)")
        }

        decisionHandler(.allow)
    }


    // MARK: - External URL

    private func openExternalURL(_ url: URL) {

        guard UIApplication.shared.canOpenURL(url) else {
            print("⚠️ Cannot open URL:")
            print("   \(url.absoluteString)")
            return
        }

        UIApplication.shared.open(
            url,
            options: [:],
            completionHandler: { success in

                if success {
                    print("✅ Opened externally:")
                    print("   \(url.absoluteString)")
                } else {
                    print("❌ Failed to open externally:")
                    print("   \(url.absoluteString)")
                }
            }
        )
    }


    // MARK: - Google Maps Detection

    private func isGoogleMapsUrl(url: URL) -> Bool {

        guard let host = url.host?.lowercased() else {
            return false
        }

        let path = url.path.lowercased()

        return host == "maps.google.com" ||
               host == "maps.app.goo.gl" ||
               host == "www.google.com" && path.hasPrefix("/maps") ||
               host.hasSuffix("google.com") && path.hasPrefix("/maps")
    }


    // MARK: - Social / App URL Detection

    private func isSocialOrAppUrl(urlString: String) -> Bool {

        let lowercasedURL = urlString.lowercased()

        let targets = [
            "whatsapp.com",
            "pinterest.com",
            "facebook.com",
            "twitter.com",
            "x.com",
            "instagram.com",
            "linkedin.com",
            "open.spotify.com",
            "telegram.me",
            "t.me"
        ]

        return targets.contains {
            lowercasedURL.contains($0)
        }
    }


    // MARK: - JavaScript Share Overrides

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
                            postElem.getAttribute('data-post-id');
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

                    var target = e.target.closest(
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
                        target.closest('[data-post-id]');

                    var postId =
                        postContainer
                            ? postContainer.getAttribute('data-post-id')
                            : null;


                    window.webkit.messageHandlers.shareText.postMessage(
                        getPostUrlFromId(postId)
                    );

                },
                true
            );

        })()
        """

        webView.evaluateJavaScript(js) { result, error in

            if let error = error {
                print("⚠️ Share JS injection error:")
                print(error.localizedDescription)
            } else {
                print("✅ Share JS injected")
            }
        }
    }


    // MARK: - Send Event To JavaScript

    private func sendToJs(
        event: String,
        messageId: String
    ) {

        let escapedEvent =
            event
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")

        let escapedMessageId =
            messageId
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")


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

        if let msgId = currentMessageId {

            sendToJs(
                event: "onSpeechStart",
                messageId: msgId
            )
        }
    }


    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {

        if let msgId = currentMessageId {

            sendToJs(
                event: "onSpeechEnd",
                messageId: msgId
            )
        }

        currentMessageId = nil
    }


    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {

        if let msgId = currentMessageId {

            sendToJs(
                event: "onSpeechEnd",
                messageId: msgId
            )
        }

        currentMessageId = nil
    }
}


// MARK: - WKScriptMessageHandler

extension ViewController: WKScriptMessageHandler {

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {

        guard let body = message.body as? String else {
            print("⚠️ JS message body is not a String")
            return
        }


        switch message.name {


        // ---------------------------------------------------------
        // Share
        // ---------------------------------------------------------

        case "shareText":

            let activityVC =
                UIActivityViewController(
                    activityItems: [body],
                    applicationActivities: nil
                )


            if let popoverController =
                activityVC.popoverPresentationController {

                popoverController.sourceView = self.view

                popoverController.sourceRect =
                    CGRect(
                        x: self.view.bounds.midX,
                        y: self.view.bounds.midY,
                        width: 0,
                        height: 0
                    )

                popoverController.permittedArrowDirections = []
            }


            present(
                activityVC,
                animated: true
            )


        // ---------------------------------------------------------
        // Authentication token
        // ---------------------------------------------------------

        case "getAuthToken":

            print("🔑 Device Authorization Token received:")
            print(body)

            // IMPORTANT:
            //
            // Your original code only printed this token.
            //
            // I have intentionally NOT invented token-storage or
            // authentication logic here because the uploaded
            // ViewController does not define what this token is
            // supposed to contain or how the website expects it
            // to be returned.
            //
            // If your website requires native authentication,
            // this is the section that needs to be connected to
            // the actual authentication flow.


        // ---------------------------------------------------------
        // Text To Speech
        // ---------------------------------------------------------

        case "speakText":

            guard let synthesizer = speechSynthesizer else {
                return
            }


            // Stop current speech

            if synthesizer.isSpeaking {

                synthesizer.stopSpeaking(
                    at: .immediate
                )


                if let msgId = currentMessageId {

                    sendToJs(
                        event: "onSpeechEnd",
                        messageId: msgId
                    )
                }

                currentMessageId = nil

                return
            }


            // Current implementation uses a local identifier.
            // Keep this compatible with your existing web code.

            currentMessageId = "ttsMessageId"


            let utterance =
                AVSpeechUtterance(string: body)

            utterance.voice =
                AVSpeechSynthesisVoice(
                    language: "en-US"
                )

            synthesizer.speak(utterance)


        default:

            print("⚠️ Unknown JS message:")
            print(message.name)
        }
    }
}

