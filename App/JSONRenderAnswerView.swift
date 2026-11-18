import SwiftUI
import UIKit

struct JSONRenderAnswerView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.openURL) private var openURL
  var envelope: JSONRenderEnvelope
  var text: String
  var isStreaming: Bool
  var messageID: UUID?
  var restoredSnapshot: JSONRenderSnapshot?
  var onSnapshot: ((JSONRenderSnapshot) -> Void)?
  @State private var height = 100.0
  @State private var failure = false
  @State private var reloadID = UUID()
  @State private var localID = UUID()
  @State private var linkURL: URL?
  @State private var showsLink = false
  @State private var linkCompletion: ((Bool, String) -> Void)?

  var body: some View {
    let fingerprint = JSONRenderSnapshot.fingerprint(text)
    let generation = model.aiWorkspaceGeneration
    let conversationID = model.aiConversationID
    let workspaceID = model.currentTeamID
    let restored = restoredSnapshot.flatMap { $0.isValid && $0.fingerprint == fingerprint ? $0 : nil }
    let snapshot = model.jsonRenderSnapshot(messageID: messageID, fingerprint: fingerprint) ?? restored
    let rendered = !isStreaming ? snapshot.map { JSONRenderEnvelope(markdown: envelope.markdown,
      segments: [.init(format: "json", text: $0.specJSON, complete: true)], exceedsLimit: false) } ?? envelope : envelope
    let identity = "\(generation)|\(conversationID)|\(messageID ?? localID)|\(reloadID)"
    VStack(alignment: .leading, spacing: 8) {
      if envelope.exceedsLimit {
        Text("構造化表示が大きすぎるため、本文を表示しています。")
          .font(.footnote).foregroundStyle(.secondary)
      } else {
        JSONRenderWebView(envelope: rendered, isStreaming: isStreaming, identity: identity,
          fingerprint: fingerprint, savedState: object(snapshot?.stateJSON),
          previousSpec: model.previousJSONRenderSpec(before: messageID), dark: colorScheme == .dark,
          fontSize: fontSize, reduceMotion: reduceMotion,
          onHeight: { if abs(height - $0) > 1 { height = $0 } },
          onState: { body in
            guard model.acceptsJSONRenderInteraction(messageID: messageID, fingerprint: fingerprint,
              generation: generation, conversationID: conversationID, workspaceID: workspaceID) else { return }
            if let messageID {
              model.saveJSONRenderSnapshot(body, messageID: messageID, fingerprint: fingerprint,
                generation: generation, conversationID: conversationID, workspaceID: workspaceID)
            }
            if let snapshot = JSONRenderSnapshot.make(body: body, fingerprint: fingerprint) { onSnapshot?(snapshot) }
          },
          onAction: { request in
            guard model.acceptsJSONRenderInteraction(messageID: messageID, fingerprint: fingerprint,
              generation: generation, conversationID: conversationID, workspaceID: workspaceID) else {
              return (false, "会話の状態が変わりました。もう一度操作してください。")
            }
            switch request.action {
            case .copyText:
              UIPasteboard.general.string = request.params["text"] ?? ""
              return (true, "コピーしました。")
            case .askAI:
              let success = model.stageJSONRenderQuestion(request.params["prompt"] ?? "")
              return (success, success ? "質問を入力欄に用意しました。確認して送信してください。" : "入力中の内容を保持しています。")
            case .completeTask:
              guard let messageID, let id = request.params["id"].flatMap(UUID.init(uuidString:)) else { return (false, "この回答で参照できるタスクではありません。") }
              return await withCheckedContinuation { continuation in
                model.completeInterfaceTask(id, messageID: messageID) { success, message in
                  continuation.resume(returning: (success, message))
                }
              }
            case .openURL:
              guard let url = request.params["url"].flatMap(URL.init(string:)), url.scheme?.lowercased() == "https",
                    url.host != nil, url.user == nil, url.password == nil, !showsLink else { return (false, "このリンクは開けません。") }
              return await withCheckedContinuation { continuation in
                linkURL = url
                linkCompletion = { continuation.resume(returning: ($0, $1)) }
                showsLink = true
              }
            }
          }, onFailure: { if !isStreaming { failure = true } })
          .id(reloadID)
          .frame(height: max(1, height))
          .accessibilityLabel("操作できる生成回答")
        if failure {
          Button("構造化表示を再読み込み", icon: .arrowClockwise) {
            failure = false
            reloadID = UUID()
          }.font(.footnote).frame(minHeight: 44)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .confirmationDialog("リンクを開く", isPresented: $showsLink, titleVisibility: .visible) {
      Button("ブラウザで開く") {
        guard let linkURL else { finishLink(false) ; return }
        let completion = linkCompletion
        linkCompletion = nil
        self.linkURL = nil
        openURL(linkURL) { success in completion?(success, success ? "リンクを開きました。" : "リンクは開いていません。") }
      }
      Button("キャンセル", role: .cancel) { finishLink(false) }
    } message: { Text(linkURL?.absoluteString ?? "") }
    .onChange(of: showsLink) { _, shown in if !shown, linkCompletion != nil { finishLink(false) } }
    .onDisappear { finishLink(false) }
  }

  private var fontSize: Double {
    // The WebKit document follows SwiftUI's Dynamic Type, including overrides.
    switch dynamicTypeSize {
    case .xSmall: 14
    case .small: 15
    case .medium: 16
    case .large: 17
    case .xLarge: 19
    case .xxLarge: 21
    case .xxxLarge: 23
    case .accessibility1: 28
    case .accessibility2: 33
    case .accessibility3: 40
    case .accessibility4: 47
    case .accessibility5: 53
    @unknown default: 17
    }
  }

  private func object(_ json: String?) -> [String: Any]? {
    json?.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
  }

  private func finishLink(_ success: Bool) {
    let completion = linkCompletion
    linkCompletion = nil
    linkURL = nil
    completion?(success, success ? "リンクを開きました。" : "リンクは開いていません。")
  }
}
