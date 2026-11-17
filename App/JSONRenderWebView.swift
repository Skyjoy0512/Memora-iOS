import SwiftUI
import WebKit

/// Only the bundled upstream runtime executes JavaScript. Model output enters
/// through structured arguments; it is never inserted into HTML or source code.
struct JSONRenderWebView: UIViewRepresentable {
  var envelope: JSONRenderEnvelope
  var isStreaming: Bool
  var identity: String
  var fingerprint: String
  var savedState: [String: Any]?
  var previousSpec: [String: Any]?
  var dark: Bool
  var fontSize: Double
  var reduceMotion: Bool
  var onHeight: (Double) -> Void
  var onState: ([String: Any]) -> Void
  var onAction: (JSONRenderActionRequest) async -> (Bool, String)
  var onFailure: () -> Void

  func makeCoordinator() -> Coordinator { Coordinator(owner: self) }

  func makeUIView(context: Context) -> WKWebView {
    let config = WKWebViewConfiguration()
    config.websiteDataStore = .nonPersistent()
    config.mediaTypesRequiringUserActionForPlayback = .all
    config.allowsInlineMediaPlayback = false
    config.userContentController.add(context.coordinator, name: "jsonRender")
    let view = WKWebView(frame: .zero, configuration: config)
    view.isOpaque = false
    view.backgroundColor = .clear
    view.scrollView.backgroundColor = .clear
    view.scrollView.isScrollEnabled = true
    view.scrollView.bounces = false
    view.navigationDelegate = context.coordinator
    context.coordinator.webView = view
    if let url = Bundle.main.url(forResource: "JSONRenderRuntime", withExtension: "html") {
      context.coordinator.resourceURL = url
      view.loadFileURL(url, allowingReadAccessTo: url)
    } else { onFailure() }
    return view
  }

  func updateUIView(_ view: WKWebView, context: Context) {
    context.coordinator.update(self)
  }

  static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
    coordinator.isActive = false
    view.stopLoading()
    view.configuration.userContentController.removeScriptMessageHandler(forName: "jsonRender")
    view.navigationDelegate = nil
  }

  @MainActor
  final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    var owner: JSONRenderWebView
    weak var webView: WKWebView?
    var resourceURL: URL?
    var isActive = true
    private var ready = false
    private var token = UUID().uuidString
    private var lastSignature = ""
    private var lastState = ""

    init(owner: JSONRenderWebView) { self.owner = owner }

    func update(_ owner: JSONRenderWebView) {
      if self.owner.identity != owner.identity {
        token = UUID().uuidString
        lastSignature = ""
        lastState = ""
      }
      self.owner = owner
      sendIfNeeded()
    }

    private func sendIfNeeded() {
      guard ready, isActive, let webView,
            let segments = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(owner.envelope.segments)) else { return }
      let signature = owner.fingerprint + "|\(owner.isStreaming)|\(owner.dark)|\(owner.fontSize)|\(owner.reduceMotion)|" + token
      guard signature != lastSignature else { return }
      lastSignature = signature
      var payload: [String: Any] = ["segments": segments, "streaming": owner.isStreaming,
        "interactive": !owner.isStreaming, "identity": owner.identity, "fingerprint": owner.fingerprint,
        "dark": owner.dark, "fontSize": owner.fontSize, "reduceMotion": owner.reduceMotion, "token": token]
      if let state = owner.savedState { payload["savedState"] = state }
      if let spec = owner.previousSpec { payload["previousSpec"] = spec }
      webView.callAsyncJavaScript("window.memoraJSONRender.receive(payload)", arguments: ["payload": payload], in: nil, in: .page) { [weak self] result in
        if case .failure = result { self?.owner.onFailure() }
      }
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
      guard isActive, message.frameInfo.isMainFrame, message.frameInfo.request.url?.isFileURL == true,
            message.frameInfo.request.url?.standardizedFileURL == resourceURL?.standardizedFileURL,
            let body = message.body as? [String: Any], let kind = body["kind"] as? String else { return }
      if kind == "ready" { ready = true; sendIfNeeded(); return }
      guard body["token"] as? String == token, body["fingerprint"] as? String == owner.fingerprint else { return }
      switch kind {
      case "height":
        if let height = body["height"] as? Double, height.isFinite, height >= 0, height <= 50_000 { owner.onHeight(height) }
      case "state":
        guard !owner.isStreaming, let data = try? JSONSerialization.data(withJSONObject: body), data.count <= 512 * 1_024,
              let json = String(data: data, encoding: .utf8), json != lastState else { return }
        lastState = json
        owner.onState(body)
      case "action":
        guard !owner.isStreaming, let request = JSONRenderActionRequest(body: body) else { return }
        let startedToken = token
        let startedFingerprint = owner.fingerprint
        let action = owner.onAction
        Task { [weak self] in
          let result = await action(request)
          guard let self, isActive, token == startedToken, owner.fingerprint == startedFingerprint else { return }
          webView?.callAsyncJavaScript("window.memoraJSONRender.resolve(id,ok,result)", arguments: [
            "id": request.id, "ok": result.0, "result": ["message": result.1]
          ], in: nil, in: .page, completionHandler: nil)
        }
      case "error": owner.onFailure()
      default: break
      }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
      // CSP blocks subresources/network; the delegate also blocks navigation,
      // new windows and custom schemes before any request can leave the app.
      if navigationAction.request.url?.standardizedFileURL == resourceURL?.standardizedFileURL {
        decisionHandler(.allow)
      } else { decisionHandler(.cancel) }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { owner.onFailure() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { owner.onFailure() }
  }
}
