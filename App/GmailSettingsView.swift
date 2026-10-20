import SwiftUI

/// Connects Gmail read-only, so the Ask AI agent can search and read mail.
struct GmailSettingsView: View {
  @State private var gmail = GmailService.shared
  @State private var errorMessage: String?
  @State private var isConfirmingDisconnect = false

  var body: some View {
    MemoraForm {
      Section {
        if gmail.isConnected {
          LabeledContent("連携中のアカウント", value: gmail.connectedEmail ?? "Gmail")
          NavigationLink {
            GlossaryView()
          } label: {
            Label("メールから用語集を作る", icon: .characterBookClosed)
          }
          Button("連携を解除", role: .destructive) {
            isConfirmingDisconnect = true
          }
        } else {
          Button {
            connect()
          } label: {
            HStack {
              Label("Gmailと連携", icon: .envelopeOpen)
              Spacer()
              if gmail.isWorking { ProgressView() }
            }
          }
          .disabled(!GmailService.isConfigured || gmail.isWorking)
        }
      } footer: {
        Text("読み取り専用で連携します。Ask AIのエージェントがメールを検索して読めるようになります。送信・削除・変更はしません。読んだメールは、質問に答えるため選んでいるAIへ送られます。")
      }

      if !GmailService.isConfigured {
        Section {
          Label("このビルドにはGoogleのOAuthクライアントIDがまだ設定されていません。設定されるまで連携できません。", icon: .exclamationmarkTriangle)
            .foregroundStyle(.secondary)
        }
      }

      if let errorMessage {
        Section {
          Label(errorMessage, icon: .exclamationmarkTriangle)
            .foregroundStyle(.secondary)
        }
      }
    }
    .navigationTitle("Gmail")
    .navigationBarTitleDisplayMode(.inline)
    .confirmationDialog("Gmailとの連携を解除しますか？", isPresented: $isConfirmingDisconnect, titleVisibility: .visible) {
      Button("連携を解除", role: .destructive) {
        Task { await gmail.disconnect() }
      }
      Button("キャンセル", role: .cancel) {}
    }
  }

  private func connect() {
    errorMessage = nil
    Task {
      do {
        try await gmail.connect()
      } catch GmailError.cancelled {
        // Closing Google's sheet is not an error worth showing.
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }
}
