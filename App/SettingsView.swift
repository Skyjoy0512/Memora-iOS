import SwiftUI

struct SettingsView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var showsCloseButton = true
  @AppStorage("memora.transcriptionEngine") private var transcriptionEngine = TranscriptionEngine.automatic
  @AppStorage("memora.transcriptionLanguage") private var transcriptionLanguage = RecognitionLanguage.japanese
  @State private var isDeleteConfirmationPresented = false
  @State private var isSignOutConfirmationPresented = false
  @State private var isAccountDeletionPresented = false

  var body: some View {
    NavigationStack {
      Form {
        Section {
          if let account = model.account {
            Label {
              VStack(alignment: .leading, spacing: 3) {
                Text(account.displayName)
                  .font(.body.weight(.medium))
                Text(account.email)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                Text("\(account.provider.label)でサインイン中")
                  .font(.caption2)
                  .foregroundStyle(.secondary)
              }
              .padding(.vertical, 2)
            } icon: {
              Image(systemName: "person.crop.circle.fill")
                .foregroundStyle(.primary)
            }

            Button("サインアウト", systemImage: "rectangle.portrait.and.arrow.right") {
              isSignOutConfirmationPresented = true
            }
          } else {
            Label {
              LabeledContent("状態", value: "このiPhoneのみ")
            } icon: {
              Image(systemName: "person")
                .foregroundStyle(.primary)
            }

            Button("サインイン / 新規登録", systemImage: "person.badge.key") {
              model.isAuthPresented = true
            }
          }
        } header: {
          Text("アカウント")
        } footer: {
          Text("同期とアカウントはまだ接続されていません。録音と整理は、このiPhoneの中で使えます。")
        }

        Section {
          Button {
            model.isPaywallPresented = true
          } label: {
            LabeledContent {
              Text(model.isSubscribed ? "Plus" : "Free")
                .foregroundStyle(.secondary)
            } label: {
              Label("Memora Plus", systemImage: "sparkles")
            }
          }
        } header: {
          Text("プラン")
        } footer: {
          Text("購入と利用回数の管理はまだ接続されていません。")
        }

        Section {
          NavigationLink {
            SpeechRecognitionSettingsView()
          } label: {
            LabeledContent("文字起こし", value: "\(transcriptionEngine.label) · \(transcriptionLanguage.label)")
          }

          NavigationLink {
            AISettingsView()
          } label: {
            LabeledContent("AI整理", value: model.aiEngine.label)
          }

          NavigationLink {
            SummaryTemplateMarketplaceView()
          } label: {
            LabeledContent(
              "要約テンプレート",
              value: model.installedTemplateIDs.isEmpty ? "標準" : "\(model.installedTemplateIDs.count)個追加"
            )
          }
        } header: {
          Text("処理")
        } footer: {
          Text("通常は変更不要です。端末やOSに合う方法をMemoraが選びます。")
        }

        Section("デバイス") {
          NavigationLink {
            ExternalRecorderSettingsView()
          } label: {
            LabeledContent("外部レコーダー", value: model.omiPairingManager.state.shortLabel)
          }
        }

        Section("連携") {
          NavigationLink {
            NotionSettingsView()
          } label: {
            LabeledContent("Notion", value: NotionService.isConfigured ? "設定済み" : "未設定")
          }

          NavigationLink {
            MCPSettingsView()
          } label: {
            LabeledContent("ChatGPT (MCP)", value: MCPIntegration.isConfigured ? "設定済み" : "未設定")
          }
        }

        Section("プライバシーと保存") {
          NavigationLink {
            PrivacyStorageView()
          } label: {
            Label("データの保存先", systemImage: "lock.shield")
          }

          LabeledContent("クラウド保管", value: model.cloudStorageEnabled ? "オン" : "オフ")

          NavigationLink {
            SettingsBackupView()
          } label: {
            Label("バックアップ", systemImage: "externaldrive")
          }

          NavigationLink {
            RecentlyDeletedView()
          } label: {
            LabeledContent(
              "最近削除した項目",
              value: model.trashedRecords.isEmpty ? "なし" : "\(model.trashedRecords.count)件"
            )
          }
        }

        Section {
          LabeledContent("ヘルプ", value: "準備中")
          LabeledContent("プライバシーポリシー", value: "準備中")
          LabeledContent("バージョン", value: Bundle.main.appVersion)
        } header: {
          Text("サポート")
        } footer: {
          Text("公開時に実際の窓口とポリシーのURLを登録します。それまでは準備中と表示し、存在しないリンクは開けません。")
        }

        Section("プロトタイプ") {
          NavigationLink {
            StateGalleryView()
          } label: {
            Label("状態と復旧UIを確認", systemImage: "rectangle.stack.badge.play")
          }

          #if DEBUG
          // Destructive resets only exist for development; a shipped build must
          // never offer to replace or empty someone's records.
          Button("初回体験をもう一度見る", systemImage: "arrow.counterclockwise") {
            model.replayOnboarding()
            if showsCloseButton {
              dismiss()
            }
          }

          Button("デモデータを入れ直す（今の内容を置き換えます）", systemImage: "arrow.clockwise") {
            model.resetSampleContent()
          }

          Button("すべて空にしてEmptyを確認", systemImage: "tray", role: .destructive) {
            isDeleteConfirmationPresented = true
          }
          #endif
        }

        if model.isSignedIn {
          Section {
            Button("アカウントを削除", systemImage: "person.crop.circle.badge.xmark", role: .destructive) {
              isAccountDeletionPresented = true
            }
          } footer: {
            Text("アカウントと同期データを削除します。このiPhoneに保存した録音は残ります。")
          }
        }
      }
      .hideBottomBarOnScroll("settings")
      .navigationTitle("設定")
      .toolbar {
        if showsCloseButton {
          ToolbarItem(placement: .confirmationAction) {
            Button("完了") { dismiss() }
          }
        }
      }
      .confirmationDialog("サインアウトしますか？", isPresented: $isSignOutConfirmationPresented, titleVisibility: .visible) {
        Button("サインアウト", role: .destructive) {
          model.signOut()
        }
        Button("キャンセル", role: .cancel) {}
      } message: {
        Text("このiPhoneの録音と議事録はそのまま残ります。")
      }
      .confirmationDialog("アカウントを削除しますか？", isPresented: $isAccountDeletionPresented, titleVisibility: .visible) {
        Button("削除", role: .destructive) {
          model.deleteAccount()
        }
        Button("キャンセル", role: .cancel) {}
      } message: {
        Text("アカウントと同期データを削除します。取り消せません。")
      }
      .confirmationDialog("サンプルを空にしますか？", isPresented: $isDeleteConfirmationPresented, titleVisibility: .visible) {
        Button("空にする", role: .destructive) {
          model.removeAllContent()
          if showsCloseButton {
            dismiss()
          }
        }
        Button("キャンセル", role: .cancel) {}
      } message: {
        Text("録音データではなく、このプロトタイプ内の表示用サンプルだけを消します。")
      }
    }
  }
}
