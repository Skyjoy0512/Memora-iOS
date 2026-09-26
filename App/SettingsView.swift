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
  @State private var isProfileEditorPresented = false

  var body: some View {
    NavigationStack {
      Form {
        profileSection

        Section {
          if let account = model.account {
            LabeledContent {
              Text(account.provider.label)
                .foregroundStyle(.secondary)
            } label: {
              Label {
                VStack(alignment: .leading, spacing: 3) {
                  Text(account.displayName)
                    .font(.body.weight(.medium))
                  Text(account.email)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
              } icon: {
                SettingsIcon(icon: .personCropCircleFill, color: .blue)
              }
            }

            Button {
              isSignOutConfirmationPresented = true
            } label: {
              SettingsLabel("サインアウト", icon: .rectanglePortraitAndArrowRight, color: .gray)
            }
          } else {
            Button {
              model.isAuthPresented = true
            } label: {
              LabeledContent {
                Text("このiPhoneのみ")
                  .foregroundStyle(.secondary)
              } label: {
                SettingsLabel("サインイン / 新規登録", icon: .personBadgeKey, color: .blue)
              }
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
              SettingsLabel("Memora Plus", icon: .crownFill, color: .orange)
            }
          }

          if model.hasTeamPlan {
            NavigationLink {
              TeamSharesView()
            } label: {
              LabeledContent {
                Text(model.cloudSharing.receivedItems.isEmpty ? "なし" : "\(model.cloudSharing.receivedItems.count)件")
              } label: {
                SettingsLabel("チームで共有されたもの", icon: .person3Fill, color: .teal)
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
                SettingsLabel("チーム共有", icon: .person3Fill, color: .teal)
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
            LabeledContent {
              Text("\(transcriptionEngine.label) · \(transcriptionLanguage.label)")
            } label: {
              SettingsLabel("文字起こし", icon: .waveform, color: .red)
            }
          }

          NavigationLink {
            AISettingsView()
          } label: {
            LabeledContent {
              Text(model.aiEngine == .cloud ? model.aiProvider.label : model.aiEngine.label)
            } label: {
              Label {
                Text("AI整理")
              } icon: {
                if model.aiEngine == .cloud {
                  ProviderLogo(provider: model.aiProvider, size: 29)
                } else {
                  SettingsIcon(icon: .brainFill, color: .purple)
                }
              }
            }
          }

          NavigationLink {
            SummaryTemplateMarketplaceView()
          } label: {
            LabeledContent {
              Text(model.installedTemplateIDs.isEmpty ? "標準" : "\(model.installedTemplateIDs.count)個追加")
            } label: {
              SettingsLabel("要約テンプレート", icon: .docTextFill, color: .indigo)
            }
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
            LabeledContent {
              Text(model.omiPairingManager.state.shortLabel)
            } label: {
              SettingsLabel("外部レコーダー", icon: .dotRadiowavesLeftAndRightFill, color: .green)
            }
          }
        }

        Section("連携") {
          NavigationLink {
            NotionSettingsView()
          } label: {
            LabeledContent {
              Text(NotionService.isConfigured ? "設定済み" : "未設定")
            } label: {
              SettingsLabel("Notion", icon: .notionLogo, color: Color(white: 0.15))
            }
          }

          NavigationLink {
            MCPSettingsView()
          } label: {
            LabeledContent {
              Text(MCPIntegration.isConfigured ? "設定済み" : "未設定")
            } label: {
              SettingsLabel("ChatGPT (MCP)", icon: .plugsConnectedFill, color: .mint)
            }
          }
        }

        Section {
          Toggle(isOn: autoLifeLogBinding) {
            SettingsLabel("移動と滞在を自動で記録", icon: .locationFill, color: .blue)
          }

          NavigationLink {
            ExcludedPlacesView()
          } label: {
            LabeledContent {
              Text(excludedPlaceCount == 0 ? "なし" : "\(excludedPlaceCount)件")
            } label: {
              SettingsLabel("記録しない場所", icon: .mappinSlashFill, color: .pink)
            }
          }

          Toggle(isOn: calendarEventsBinding) {
            SettingsLabel("カレンダーの予定を表示", icon: .calendarFill, color: .red)
          }

          NavigationLink {
            CalendarSelectionView()
          } label: {
            SettingsLabel("表示するカレンダー", icon: .calendarBadgeCheckmarkFill, color: .orange)
          }
          .disabled(!showCalendarEvents)
        } header: {
          Text("ジャーナル")
        } footer: {
          Text("位置情報はこのiPhoneの中だけで使い、外部へ送信しません。電池への影響を抑えるため、駅の判定はおおよそです。カレンダーの予定は保存せず、表示のたびに読み込みます。")
        }

        Section {
          Toggle(isOn: $appLockEnabled) {
            SettingsLabel("Face IDでロック", icon: .faceidFill, color: .green)
          }

          NavigationLink {
            PrivacyStorageView()
          } label: {
            SettingsLabel("データの保存先", icon: .lockShieldFill, color: .blue)
          }

          NavigationLink {
            StorageUsageView()
          } label: {
            SettingsLabel("保存容量", icon: .internaldriveFill, color: .gray)
          }

          LabeledContent {
            Text(model.cloudStorageEnabled ? "オン" : "オフ")
          } label: {
            SettingsLabel("クラウド保管", icon: .cloudFill, color: .cyan)
          }

          NavigationLink {
            SettingsBackupView()
          } label: {
            SettingsLabel("バックアップ", icon: .externaldriveFill, color: .brown)
          }

          NavigationLink {
            RecentlyDeletedView()
          } label: {
            LabeledContent {
              Text(model.trashedRecords.isEmpty ? "なし" : "\(model.trashedRecords.count)件")
            } label: {
              SettingsLabel("最近削除した項目", icon: .trashFill, color: .red)
            }
          }
        } header: {
          Text("プライバシーと保存")
        } footer: {
          Text("Face IDでロックは、アプリを開いたときと、5分以上離れたあとに戻ったときに解除を求めます。録音中はロックしません。")
        }

        Section {
          LabeledContent {
            Text("準備中")
          } label: {
            SettingsLabel("ヘルプ", icon: .questionmarkCircleFill, color: .blue)
          }
          LabeledContent {
            Text("準備中")
          } label: {
            SettingsLabel("プライバシーポリシー", icon: .handRaisedFill, color: .blue)
          }
          LabeledContent {
            Text(Bundle.main.appVersion)
          } label: {
            SettingsLabel("バージョン", icon: .infoCircleFill, color: .gray)
          }
        } header: {
          Text("サポート")
        } footer: {
          Text("公開時に実際の窓口とポリシーのURLを登録します。それまでは準備中と表示し、存在しないリンクは開けません。")
        }

        Section("プロトタイプ") {
          NavigationLink {
            StateGalleryView()
          } label: {
            SettingsLabel("状態と復旧UIを確認", icon: .rectangleStackFill, color: .gray)
          }

          #if DEBUG
          NavigationLink {
            PerformanceLogView()
          } label: {
            SettingsLabel("計測と自己チェック（ビルド比較用）", icon: .stopwatchFill, color: .gray)
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
            ToolbarIconButton("完了", icon: .checkmark) { dismiss() }
          }
        }
      }
      .sheet(isPresented: $isProfileEditorPresented) {
        ProfileEditorView()
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

  /// The person's picture and name at the top, as in the system Settings app.
  /// Tapping it opens the editor for the Memoji, photo, and name.
  private var profileSection: some View {
    Section {
      Button {
        isProfileEditorPresented = true
      } label: {
        VStack(spacing: 10) {
          ProfileAvatar(profile: model.profile, size: 96)
            .overlay(alignment: .bottomTrailing) {
              Image(icon: .pencil)
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(.tint, in: Circle())
                .overlay { Circle().stroke(Color(uiColor: .systemGroupedBackground), lineWidth: 3) }
            }

          VStack(spacing: 3) {
            Text(profileName)
              .font(.title3.weight(.semibold))
              .foregroundStyle(.primary)
            Text("ミー文字・写真・名前を編集")
              .font(.subheadline)
              .foregroundStyle(.tint)
          }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .listRowBackground(Color.clear)
      .accessibilityLabel("プロフィール \(profileName)")
      .accessibilityHint("ミー文字・写真・名前を編集します")
    }
  }

  private var profileName: String {
    let name = model.profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
    if !name.isEmpty { return name }
    return model.account?.displayName ?? "名前を設定"
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
