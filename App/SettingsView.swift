import SwiftUI

struct SettingsView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var showsCloseButton = true
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
          Text(model.isSignedIn
               ? "会議とタスクを同じアカウントの端末で同期します。"
               : "サインインしなくても録音とローカル文字起こしを試せます。同期が必要になった時に接続できます。")
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
          Text(model.isSubscribed
               ? "高度なAI整理を制限なく利用できます。"
               : "あと4回、高度なAI整理を利用できます。")
        }

        Section {
          NavigationLink {
            SpeechRecognitionSettingsView()
          } label: {
            LabeledContent("文字起こし", value: "自動 · 日本語")
          }

          NavigationLink {
            AISettingsView()
          } label: {
            LabeledContent("AI整理", value: "自動")
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

        Section("プライバシーと保存") {
          NavigationLink {
            PrivacyStorageView()
          } label: {
            Label("データの保存先", systemImage: "lock.shield")
          }

          LabeledContent("クラウド同期", value: "オフ")
        }

        Section("サポート") {
          Link(destination: URL(string: "https://example.com/help")!) {
            Label("ヘルプ", systemImage: "questionmark")
          }
          Link(destination: URL(string: "https://example.com/privacy")!) {
            Label("プライバシーポリシー", systemImage: "hand.raised")
          }
          LabeledContent("バージョン", value: "1.0")
        }

        Section("プロトタイプ") {
          NavigationLink {
            StateGalleryView()
          } label: {
            Label("状態と復旧UIを確認", systemImage: "rectangle.stack.badge.play")
          }

          Button("初回体験をもう一度見る", systemImage: "arrow.counterclockwise") {
            model.replayOnboarding()
            if showsCloseButton {
              dismiss()
            }
          }

          Button("サンプルを復元", systemImage: "arrow.clockwise") {
            model.resetSampleContent()
          }

          Button("すべて空にしてEmptyを確認", systemImage: "tray", role: .destructive) {
            isDeleteConfirmationPresented = true
          }
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
      .compactBottomBarOnScroll()
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

private struct SpeechRecognitionSettingsView: View {
  @State private var mode = RecognitionMode.automatic
  @State private var language = RecognitionLanguage.japanese

  var body: some View {
    Form {
      Section("文字起こし方法") {
        Picker("方法", selection: $mode) {
          ForEach(RecognitionMode.allCases) { option in
            Text(option.label).tag(option)
          }
        }
        Text(mode.description)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      Section("言語") {
        Picker("主な言語", selection: $language) {
          ForEach(RecognitionLanguage.allCases) { option in
            Text(option.label).tag(option)
          }
        }
      }
    }
    .navigationTitle("文字起こし")
  }
}

private enum RecognitionMode: String, CaseIterable, Identifiable {
  case automatic
  case localOnly

  var id: Self { self }

  var label: String {
    switch self {
    case .automatic:
      "自動（おすすめ）"
    case .localOnly:
      "端末内のみ"
    }
  }

  var description: String {
    switch self {
    case .automatic:
      "端末とOSに合う方法をMemoraが選びます。外部処理を使う場合は事前に分かるよう表示します。"
    case .localOnly:
      "対応する端末では、音声を外部へ送らず文字起こしします。"
    }
  }
}

private enum RecognitionLanguage: String, CaseIterable, Identifiable {
  case japanese
  case english
  case automatic

  var id: Self { self }

  var label: String {
    switch self {
    case .japanese:
      "日本語"
    case .english:
      "英語"
    case .automatic:
      "自動検出"
    }
  }
}

private struct AISettingsView: View {
  @State private var style = SummaryStyle.automatic
  @State private var isAPIKeySheetPresented = false

  var body: some View {
    Form {
      Section {
        Picker("まとめ方", selection: $style) {
          ForEach(SummaryStyle.allCases) { option in
            Text(option.label).tag(option)
          }
        }
      } header: {
        Text("議事録")
      } footer: {
        Text("おすすめの「自動」は、会話に合わせて要約・決定・タスク・未決事項を整理します。")
      }

      Section {
        LabeledContent("現在", value: "Memora")
        Button("APIキーを設定", systemImage: "key") {
          isAPIKeySheetPresented = true
        }
      } header: {
        Text("AIプロバイダー")
      } footer: {
        Text("シークレットはKeychainに保存し、設定画面にも再表示しません。")
      }
    }
    .navigationTitle("AI整理")
    .sheet(isPresented: $isAPIKeySheetPresented) {
      APIKeySheet()
    }
  }
}

private enum SummaryStyle: String, CaseIterable, Identifiable {
  case automatic
  case summary
  case detailed
  case actionFocused

  var id: Self { self }

  var label: String {
    switch self {
    case .automatic:
      "自動（おすすめ）"
    case .summary:
      "短い要約"
    case .detailed:
      "詳しい議事録"
    case .actionFocused:
      "アクション重視"
    }
  }
}

private struct APIKeySheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var key = ""

  var body: some View {
    NavigationStack {
      Form {
        Section {
          SecureField("キーを入力", text: $key)
            .textContentType(.password)
        } header: {
          Text("APIキー")
        } footer: {
          Text("保存後は値を表示しません。削除と置き換えだけができます。")
        }
      }
      .navigationTitle("APIキーを設定")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("キャンセル") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("安全に保存") { dismiss() }
            .disabled(key.isEmpty)
        }
      }
    }
    .presentationDetents([.medium])
  }
}

private struct PrivacyStorageView: View {
  var body: some View {
    List {
      Section {
        Label {
          VStack(alignment: .leading, spacing: 4) {
            Text("このiPhone")
              .font(.headline)
            Text("録音・文字起こし・議事録を保存")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
        } icon: {
          Image(systemName: "iphone")
            .foregroundStyle(.primary)
        }
      }

      Section {
        LabeledContent("高度なAI整理", value: "実行前に表示")
        LabeledContent("クラウド同期", value: "オフ")
      } header: {
        Text("外部へ送られる可能性があるもの")
      } footer: {
        Text("処理先が変わる時だけ、操作の流れを止めない形で確認します。")
      }
    }
    .navigationTitle("データの保存先")
  }
}
