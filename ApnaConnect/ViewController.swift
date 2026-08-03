import UIKit
import WebKit
import AVFoundation

class ViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, AVSpeechSynthesizerDelegate {

    private var webView: WKWebView!
    private var speechSynthesizer: AVSpeechSynthesizer?
    private var currentMessageId: String?
    
    // Splash UI Elements
    private var splashContainer: UIView!
    private var splashLogo: UIImageView!
    
    private var pageLoaded = false
    private var splashMinTimePassed = false
    private let splashMinTime: TimeInterval = 2.0 // 2 seconds

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // 1. Initialize Speech Engine
        speechSynthesizer = AVSpeechSynthesizer()
        speechSynthesizer?.delegate = self
        
        // 2. Setup Base View & Splash Screen
        setupSplashUI()
        
        // 3. Setup WebView Configuration & JS Bridge
        setupWebView()
        
        // 4. Enforce Minimum Splash Timer
        DispatchQueue.main.asyncAfter(deadline: .now() + splashMinTime) { [weak self] in
            self?.splashMinTimePassed = true
            self?.maybeHideSplash()
        }
    }
    
    // MARK: - Splash Management
    private func setupSplashUI() {
        view.backgroundColor = .white
        
        splashContainer = UIView(frame: view.bounds)
        splashContainer.backgroundColor = .white // Match your activity splash container background
        splashContainer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        splashLogo = UIImageView()
        splashLogo.image = UIImage(named: "splashLogo") // Ensure this asset exists in your Assets.xcassets
        splashLogo.contentMode = .scaleAspectFit
        splashLogo.translatesAutoresizingMaskIntoConstraints = false
        
        splashContainer.addSubview(splashLogo)
        view.addSubview(splashContainer)
        
        NSLayoutConstraint.activate([
            splashLogo.centerXAnchor.constraint(equalTo: splashContainer.centerXAnchor),
            splashLogo.centerYAnchor.constraint(equalTo: splashContainer.centerYAnchor),
            splashLogo.widthAnchor.constraint(equalToConstant: 200),
            splashLogo.heightAnchor.constraint(equalToConstant: 200)
        ])
    }
    
    private func maybeHideSplash() {
        if pageLoaded && splashMinTimePassed {
            UIView.animate(withDuration: 0.5, animations: {
                self.splashContainer.alpha = 0
            }) { _ in
                self.splashContainer.isHidden = true
                self.splashContainer.removeFromSuperview()
            }
        }
    }

    // MARK: - WebView Setup
    private func setupWebView() {
        let webConfiguration = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        
        // Register Javascript Bridge Interface Message Handlers
        userContentController.add(self, name: "shareText")
        userContentController.add(self, name: "getAuthToken")
        userContentController.add(self, name: "speakText")
        
        webConfiguration.userContentController = userContentController
        
        // Match Android settings: Javascript, DOM storage, inline media permissions
        webConfiguration.preferences.javaScriptEnabled = true
        webConfiguration.setValue(true, forKey: "allowUniversalAccessFromFileURLs")
        webConfiguration.allowsInlineMediaPlayback = true
        
        // In Xcode 14.3, microphone permissions for WebRTC inside WebView are handled inline here
        if #available(iOS 14.3, *) {
            webConfiguration.mediaTypesRequiringUserActionForPlayback = []
        }
        
        // Instantiate using the safe area frame to provide edge-to-edge support automatically
        webView = WKWebView(frame: view.bounds, configuration: webConfiguration)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.navigationDelegate = self
        webView.uiDelegate = self // Required for handling file upload choosers
        
        // Insert WebView below the splash layer container
        view.insertSubview(webView, at: 0)
        
        if let url = URL(string: "https://apnaconnect.com.au") {
            let request = URLRequest(url: url)
            webView.load(request)
        }
    }
    
    // MARK: - WKNavigationDelegate (Url Interceptor Pipeline)
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decidePolicyFor windowFeatures: WKWindowFeatures, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        
        let urlString = url.absoluteString
        
        // Protocols handling (tel: and mailto:)
        if urlString.hasPrefix("tel:") || urlString.hasPrefix("mailto:") {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
            decisionHandler(.cancel)
            return
        }
        
        // Deep-linking interceptor rules (Maps & Social Ecosystems)
        if isGoogleMapsUrl(url: url) || isSocialOrAppUrl(urlString: urlString) {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                decisionHandler(.cancel) // Intercepted and routed out to the system app
                return
            }
        }
        
        decisionHandler(.allow)
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageLoaded = true
        maybeHideSplash()
        
        // Inject JS Share Interceptor Overrides directly into the frame environment
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.injectShareOverrides()
        }
    }
    
    // MARK: - Helper Pattern Handlers
    private func isGoogleMapsUrl(url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let path = url.path.lowercased()
        
        return host == "maps.google.com" ||
               host == "maps.app.goo.gl" ||
               (host.hasSuffix("google.com") && path.hasPrefix("/maps"))
    }
    
    private func isSocialOrAppUrl(urlString: String) -> Bool {
        let targets = [
            "whatsapp.com", "pinterest.com", "facebook.com",
            "twitter.com", "x.com", "instagram.com",
            "linkedin.com", "open.spotify.com", "telegram.me", "t.me"
        ]
        return targets.contains { urlString.contains($0) }
    }
    
    // MARK: - JavaScript Injection Bridge (Replaces Javascript String processing)
    private func injectShareOverrides() {
        let js = """
        (function() {
            if (typeof window.webkit === 'undefined' || typeof window.webkit.messageHandlers === 'undefined') return;
            console.log('🔧 iOS Share interceptor active');
            
            function getPostUrlFromId(postId) {
                if (window.location.pathname.includes('/post/') || window.location.search.includes('link1=post')) {
                    return window.location.href;
                }
                return window.location.origin + '/index.php?link1=post&id=' + postId;
            }
            
            if (window.SharePostRTE) {
                window.SharePostRTE.show = function() {
                    var postId = null;
                    var postElem = document.querySelector('[data-post-id]');
                    if (postElem) postId = postElem.getAttribute('data-post-id');
                    window.webkit.messageHandlers.shareText.postMessage(getPostUrlFromId(postId));
                    return false;
                };
                window.SharePostRTE.open = function() { window.SharePostRTE.show(); return false; };
            }
            
            document.body.addEventListener('click', function(e) {
                var target = e.target.closest('.stat-item, .btn, [onclick*="Share"], [title*="share"]');
                if (!target) return;
                var isShareBtn = false;
                if (target.getAttribute('title') && target.getAttribute('title').toLowerCase().includes('share')) isShareBtn = true;
                if (target.innerHTML && target.innerHTML.toLowerCase().includes('share')) isShareBtn = true;
                if (target.onclick && target.onclick.toString().includes('Share')) isShareBtn = true;
                if (!isShareBtn) return;
                
                e.preventDefault();
                e.stopPropagation();
                e.stopImmediatePropagation();
                
                var postContainer = target.closest('[data-post-id]');
                var postId = postContainer ? postContainer.getAttribute('data-post-id') : null;
                window.webkit.messageHandlers.shareText.postMessage(getPostUrlFromId(postId));
            }, true);
        })()
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
    
    private func sendToJs(event: String, messageId: String) {
        let script = "window.dispatchEvent(new CustomEvent('AndroidTTSEvent', { detail: { event: '\(event)', messageId: '\(messageId)' } }))"
        webView.evaluateJavaScript(script, completionHandler: nil)
    }
    
    // MARK: - AVSpeechSynthesizerDelegate (TTS Lifecycle Updates)
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        if let msgId = currentMessageId { sendToJs(event: "onSpeechStart", messageId: msgId) }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        if let msgId = currentMessageId { sendToJs(event: "onSpeechEnd", messageId: msgId) }
        currentMessageId = nil
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        if let msgId = currentMessageId { sendToJs(event: "onSpeechEnd", messageId: msgId) }
        currentMessageId = nil
    }
}

// MARK: - WKScriptMessageHandler (Native Execution of JS Methods)
extension ViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? String else { return }
        
        switch message.name {
        case "shareText":
            // Replicates the native UI Share Dialog sheet sheet launcher
            let activityVC = UIActivityViewController(activityItems: [body], applicationActivities: nil)
            if let popoverController = activityVC.popoverPresentationController {
                popoverController.sourceView = self.view // Prevent iPad layout crashes
                popoverController.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 0, height: 0)
                popoverController.permittedArrowDirections = []
            }
            present(activityVC, animated: true, completion: nil)
            
        case "getAuthToken":
            print("🔑 Device Authorization Token received: \(body)")
            
        case "speakText":
            guard let synthesizer = speechSynthesizer else { return }
            
            if synthesizer.isSpeaking {
                synthesizer.stopSpeaking(at: .immediate)
                if let msgId = currentMessageId { sendToJs(event: "onSpeechEnd", messageId: msgId) }
                return
            }
            
            // Extract elements or assume direct incoming paragraph tracking matching Android params
            self.currentMessageId = "ttsMessageId" // Set up identifier linking callback hooks
            let utterance = AVSpeechUtterance(string: body)
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            synthesizer.speak(utterance)
            
        default:
            break
        }
    }
}



