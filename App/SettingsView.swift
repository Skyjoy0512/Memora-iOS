import SwiftUI

struct SettingsView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var showsCloseButton = true
  @AppStorage("memora.transcriptionEngine") private var transcriptionEngine = TranscriptionEngine.automatic
  @AppStorage("memora.transcriptionLanguage") private var transcriptionLanguage = RecognitionLanguage.japanese
  @AppStorage("memora.autoLifeLog.enabled") private var autoLifeLogEnabled = false
  @AppStorage("memora.journal.showCalendarEvents") private var showCalendarEvents = false
  @AppStorage("memora.appLock") private var appLockEnabled = false
  @State private var isLocationPermissionAlertPresented = false
  @State private var isCalendarPermissionAlertPresented = false
  @State private var excludedPlaceCount = AutoLocationLogger.excludedPlaces.count
  @State private var isDeleteConfirmationPresented = false
  @Environment(\.openURL) private var openURL
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
              Image(icon: .personCropCircleFill)
                .foregroundStyle(.primary)
            }

            Button("サインアウト", icon: .rectanglePortraitAndArrowRight) {
              isSignOutConfirmationPresented = true
            }
          } else {
            Label {
              LabeledContent("状態", value: "このiPhoneのみ")
            } icon: {
              Image(icon: .person)
                .foregroundStyle(.primary)
            }

            Button("サインイン / 新規登録", icon: .personBadgeKey) {
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
              Text(model.planTier?.label ?? "Free")
                .foregroundStyle(.secondary)
            } label: {
              Label("Memora Plus", icon: .sparkles)
            }
          }

          if model.hasTeamPlan {
            NavigationLink {
              TeamSharesView()
            } label: {
              LabeledContent {
                Text(model.cloudSharing.receivedItems.isEmpty ? "なし" : "\(model.cloudSharing.receivedItems.count)件")
                  .foregroundStyle(.secondary)
              } label: {
                Label("チームで共有されたもの", icon: .person3)
              }
            }
          } else {
            Button {
              model.isPaywallPresented = true
            } label: {
              LabeledContent {
                Text("チームプランで利用可")
                  .foregroundStyle(.secondary)
              } label: {
                Label("チーム共有", icon: .person3)
              }
            }
          }
        } header: {
          Text("プラン")
        } footer: {
          Text("購入はまだ接続されていません。プランはこの端末の設定として保存し、チーム共有はチームプランで利用できます。")
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

        Section {
          Toggle("移動と滞在を自動で記録", isOn: autoLifeLogBinding)

          NavigationLink {
            ExcludedPlacesView()
          } label: {
            LabeledContent(
              "記録しない場所",
              value: excludedPlaceCount == 0 ? "なし" : "\(excludedPlaceCount)件"
            )
          }

          Toggle("カレンダーの予定を表示", isOn: calendarEventsBinding)

          NavigationLink {
            CalendarSelectionView()
          } label: {
            Text("表示するカレンダー")
          }
          .disabled(!showCalendarEvents)
        } header: {
          Text("ジャーナル")
        } footer: {
          Text("位置情報はこのiPhoneの中だけで使い、外部へ送信しません。電池への影響を抑えるため、駅の判定はおおよそです。カレンダーの予定は保存せず、表示のたびに読み込みます。")
        }

        Section {
          Toggle("Face IDでロック", isOn: $appLockEnabled)

          NavigationLink {
            PrivacyStorageView()
          } label: {
            Label("データの保存先", icon: .lockShield)
          }

          NavigationLink {
            StorageUsageView()
          } label: {
            Label("保存容量", icon: .internaldrive)
          }

          LabeledContent("クラウド保管", value: model.cloudStorageEnabled ? "オン" : "オフ")

          NavigationLink {
            SettingsBackupView()
          } label: {
            Label("バックアップ", icon: .externaldrive)
          }

          NavigationLink {
            RecentlyDeletedView()
          } label: {
            LabeledContent(
              "最近削除した項目",
              value: model.trashedRecords.isEmpty ? "なし" : "\(model.trashedRecords.count)件"
            )
          }
        } header: {
          Text("プライバシーと保存")
        } footer: {
          Text("Face IDでロックは、アプリを開いたときと、5分以上離れたあとに戻ったときに解除を求めます。録音中はロックしません。")
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
            Label("状態と復旧UIを確認", icon: .rectangleStackBadgePlay)
          }

          #if DEBUG
          NavigationLink {
            PerformanceLogView()
          } label: {
            Label("計測と自己チェック（ビルド比較用）", icon: .stopwatch)
          }

          // Destructive resets only exist for development; a shipped build must
          // never offer to replace or empty someone's records.
          Button("初回体験をもう一度見る", icon: .arrowCounterclockwise) {
            model.replayOnboarding()
            if showsCloseButton {
              dismiss()
            }
          }

          Button("デモデータを入れ直す（今の内容を置き換えます）", icon: .arrowClockwise) {
            model.loadSampleContent()
          }

          Button("すべて空にしてEmptyを確認", icon: .tray, role: .destructive) {
            isDeleteConfirmationPresented = true
          }
          #endif
        }

        if model.isSignedIn {
          Section {
            Button("アカウントを削除", icon: .personCropCircleBadgeXmark, role: .destructive) {
              isAccountDeletionPresented = true
            }
          } footer: {
            Text("アカウントと同期データを削除します。このiPhoneに保存した録音は残ります。")
          }
        }
      }
      .hideBottomBarOnScroll("settings")
      .onAppear { excludedPlaceCount = AutoLocationLogger.excludedPlaces.count }
      .onDisappear {
        // A permission request the person walked away from must not surface its
        // alert on another screen later.
        AutoLocationLogger.shared.discardPendingEnable()
      }
      .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
        excludedPlaceCount = AutoLocationLogger.excludedPlaces.count
      }
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
          model.deleteSampleContent()
          if showsCloseButton {
            dismiss()
          }
        }
        Button("キャンセル", role: .cancel) {}
      } message: {
        Text("録音データではなく、このプロトタイプ内の表示用サンプルだけを消します。")
      }
      .alert("位置情報を「常に」許可してください", isPresented: $isLocationPermissionAlertPresented) {
        Button("設定を開く") {
          if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
          }
        }
        Button("キャンセル", role: .cancel) {}
      } message: {
        Text("アプリを使っていない間の移動・滞在の記録には「常に」の許可が必要です。設定の位置情報から許可してください。")
      }
      .alert("カレンダーへのアクセスが必要です", isPresented: $isCalendarPermissionAlertPresented) {
        Button("設定を開く") {
          if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
          }
        }
        Button("キャンセル", role: .cancel) {}
      } message: {
        Text("予定をジャーナルに表示するには、設定でカレンダーへのアクセスを許可してください。予定は表示のたびに読み込み、保存はしません。")
      }
    }
  }

  /// Turning the toggle on asks for calendar access the first time; a refusal
  /// puts it back and explains why.
  private var calendarEventsBinding: Binding<Bool> {
    Binding {
      showCalendarEvents
    } set: { enabled in
      guard enabled else {
        showCalendarEvents = false
        return
      }
      Task {
        let granted: Bool
        if CalendarService.access == .granted {
          granted = true
        } else {
          granted = await CalendarService.requestAccess()
        }
        if granted {
          showCalendarEvents = true
        } else {
          showCalendarEvents = false
          isCalendarPermissionAlertPresented = true
        }
      }
    }
  }

  /// Turning the toggle on asks for permission; only "always" lets the background
  /// monitoring run, so a refusal puts it back and explains why.
  private var autoLifeLogBinding: Binding<Bool> {
    Binding {
      autoLifeLogEnabled
    } set: { enabled in
      if enabled {
        AutoLocationLogger.shared.enable { granted in
          autoLifeLogEnabled = granted
          if !granted {
            isLocationPermissionAlertPresented = true
          }
        }
      } else {
        autoLifeLogEnabled = false
        AutoLocationLogger.shared.disable()
      }
    }
  }
}
