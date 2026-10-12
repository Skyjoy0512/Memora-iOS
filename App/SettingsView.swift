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
  @AppStorage("memora.prefersDarkAppearance") private var prefersDarkAppearance = false
  @AppStorage("memora.haptics.enabled") private var hapticsEnabled = true
  @State private var isLocationPermissionAlertPresented = false
  @State private var isCalendarPermissionAlertPresented = false
  @State private var appLockError: String?
  @State private var excludedPlaceCount = AutoLocationLogger.excludedPlaces.count
  @State private var isDeleteConfirmationPresented = false
  @Environment(\.openURL) private var openURL
  @State private var isSignOutConfirmationPresented = false
  @State private var isAccountDeletionPresented = false
  @State private var isProfileEditorPresented = false
  @State private var isPlanPresented = false
  @State private var isAuthPresented = false

  var body: some View {
    NavigationStack {
      Form {
        profileSection

        Section {
          SettingsPlanCard { isPlanPresented = true }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } footer: {
          Text("購入は未接続です。プランの変更は端末の設定のみで、課金されません。")
        }

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
                SettingsIcon(icon: .personCropCircleFill, color: Tint.account)
              }
            }

            Button {
              isSignOutConfirmationPresented = true
            } label: {
              SettingsLabel("サインアウト", icon: .rectanglePortraitAndArrowRight, color: Tint.account)
            }
          } else {
            Button {
              isAuthPresented = true
            } label: {
              LabeledContent {
                Text("このiPhoneのみ")
                  .foregroundStyle(.secondary)
              } label: {
                SettingsLabel("サインイン / 新規登録", icon: .personBadgeKey, color: Tint.account, artwork: .settingsSignUp)
              }
            }
          }
        } header: {
          Text("アカウント")
        } footer: {
          Text("同期・アカウントは未接続です。このiPhoneだけで使えます。")
        }

        Section {
          Button {
            isPlanPresented = true
          } label: {
            LabeledContent {
              Text(model.planName)
                .foregroundStyle(.secondary)
            } label: {
              SettingsLabel("プラン", icon: .crownFill, color: Tint.plan, artwork: .settingsPlan)
            }
          }

          NavigationLink {
            AICreditsView()
          } label: {
            LabeledContent {
              Text(creditSummary)
            } label: {
              SettingsLabel("AIクレジット", icon: .sparklesRectangleStack, color: Tint.plan, artwork: .settingsCredits)
            }
          }

          NavigationLink {
            LicenseActivationView()
          } label: {
            LabeledContent {
              Text(model.activeLicense?.company ?? "未登録")
            } label: {
              SettingsLabel("法人ライセンス", icon: .building2Fill, color: Tint.plan, artwork: .settingsLicense)
            }
          }

          if model.hasTeamPlan {
            NavigationLink {
              TeamSharesView()
            } label: {
              LabeledContent {
                Text(model.cloudSharing.receivedItems.isEmpty ? "なし" : "\(model.cloudSharing.receivedItems.count)件")
              } label: {
                SettingsLabel("チームで共有されたもの", icon: .person3Fill, color: Tint.plan, artwork: .settingsTeam)
              }
            }
          } else {
            Button {
              isPlanPresented = true
            } label: {
              LabeledContent {
                Text("チームプランで利用可")
                  .foregroundStyle(.secondary)
              } label: {
                SettingsLabel("チーム共有", icon: .person3Fill, color: Tint.plan, artwork: .settingsTeam)
              }
            }
          }
        } header: {
          Text("プラン")
        }

        Section {
          Toggle(isOn: $prefersDarkAppearance) {
            SettingsLabel("ダークモード", icon: .moonFill, color: Tint.appearance)
          }
          Toggle(isOn: $hapticsEnabled) {
            SettingsLabel("触覚フィードバック", icon: .iphone, color: Tint.appearance)
          }
        } header: {
          Text("表示と操作")
        } footer: {
          Text("タップ・選択・操作完了を振動で知らせます。録音・音声入力・声の登録中は、音声に振動が入らないよう抑えます。")
        }

        Section("パーソナライズ") {
          NavigationLink {
            OccupationSelectionView()
          } label: {
            LabeledContent {
              Text(model.occupationSummary).lineLimit(1)
            } label: {
              SettingsLabel("仕事・活動", icon: .briefcase, color: Tint.processing)
            }
          }
          NavigationLink {
            SummaryStyleSettingsView()
          } label: {
            SettingsLabel("要約スタイル", icon: .docText, color: Tint.processing)
          }
          NavigationLink {
            VoiceProfileView()
          } label: {
            SettingsLabel("自分の声を登録", icon: .personWave2, color: Tint.processing)
          }
          NavigationLink {
            SpeakerIdentificationSettingsView()
          } label: {
            SettingsLabel("話者識別", icon: .person2, color: Tint.processing)
          }
        }

        Section {
          NavigationLink {
            SpeechRecognitionSettingsView()
          } label: {
            LabeledContent {
              Text("\(transcriptionEngine.label) · \(transcriptionLanguage.label)")
            } label: {
              SettingsLabel("文字起こし", icon: .waveform, color: Tint.processing, artwork: .settingsTranscription)
            }
          }

          NavigationLink {
            AISettingsView()
          } label: {
            LabeledContent {
              Text(model.aiEngine == .cloud ? model.aiProvider.label : model.aiEngine.label)
            } label: {
              SettingsLabel("AI整理", icon: .sparkles, color: Tint.processing, artwork: .settingsIntelligence)
            }
          }

          NavigationLink {
            ResidentAgentsView()
          } label: {
            LabeledContent {
              Text(model.residentLLM == nil ? "BYOKのみ" : "\(model.residentAgents.filter(\.isEnabled).count)件オン")
            } label: {
              SettingsLabel("常駐エージェント", icon: .clockArrowCirclepath, color: Tint.processing, artwork: .settingsResidentAgent)
            }
          }

          NavigationLink {
            AIMemoryView()
          } label: {
            LabeledContent {
              Text(model.isAIMemoryEnabled ? "\(model.aiMemories.count)件" : "オフ")
            } label: {
              SettingsLabel("メモリ", icon: .brainHeadProfile, color: Tint.processing, artwork: .settingsMemory)
            }
          }

          NavigationLink {
            SummaryTemplateMarketplaceView()
          } label: {
            LabeledContent {
              Text(model.installedTemplateIDs.isEmpty ? "標準" : "\(model.installedTemplateIDs.count)個追加")
            } label: {
              SettingsLabel("要約テンプレート", icon: .docTextFill, color: Tint.processing, artwork: .settingsSummary)
            }
          }
        } header: {
          Text("処理")
        }

        Section("デバイス") {
          NavigationLink {
            ExternalRecorderSettingsView()
          } label: {
            LabeledContent {
              Text(model.omiPairingManager.state.shortLabel)
            } label: {
              SettingsLabel("外部レコーダー", icon: .dotRadiowavesLeftAndRightFill, color: Tint.device)
            }
          }
        }

        Section("連携") {
          NavigationLink {
            GmailSettingsView()
          } label: {
            LabeledContent {
              Text(GmailService.shared.isConnected ? "連携中" : "未連携")
            } label: {
              SettingsLabel("Gmail", icon: .envelopeOpen, color: Tint.integrations, artwork: .settingsGmail)
            }
          }

          NavigationLink {
            WebhookSettingsView()
          } label: {
            LabeledContent {
              Text(model.webhookEndpoints.isEmpty ? "未設定" : "\(model.webhookEndpoints.count)件")
            } label: {
              SettingsLabel("Webhook（Slack・Zapierなど）", icon: .paperplane, color: Tint.integrations, artwork: .settingsWebhook)
            }
          }

          NavigationLink {
            MCPServersView()
          } label: {
            LabeledContent {
              Text(model.mcpServers.isEmpty ? (MCPIntegration.isConfigured ? "設定済み" : "未設定") : "\(model.mcpServers.count)件")
            } label: {
              SettingsLabel("MCP", icon: .plugsConnected, color: Tint.integrations, artwork: .settingsMCP)
            }
          }

          NavigationLink {
            NotionSettingsView()
          } label: {
            LabeledContent {
              Text(NotionService.isConfigured ? "設定済み" : "未設定")
            } label: {
              SettingsLabel("Notion", icon: .notionLogo, color: Tint.integrations, artwork: .settingsNotion)
            }
          }

        }

        Section {
          Toggle(isOn: autoLifeLogBinding) {
            SettingsLabel("移動と滞在を自動で記録", icon: .locationFill, color: Tint.journal)
          }

          NavigationLink {
            ExcludedPlacesView()
          } label: {
            LabeledContent {
              Text(excludedPlaceCount == 0 ? "なし" : "\(excludedPlaceCount)件")
            } label: {
              SettingsLabel("記録しない場所", icon: .mappinSlashFill, color: Tint.journal)
            }
          }

          Toggle(isOn: calendarEventsBinding) {
            SettingsLabel("カレンダーの予定を表示", icon: .calendarFill, color: Tint.journal)
          }

          NavigationLink {
            CalendarSelectionView()
          } label: {
            SettingsLabel("表示するカレンダー", icon: .calendarBadgeCheckmarkFill, color: Tint.journal)
          }
          .disabled(!showCalendarEvents)
        } header: {
          Text("ジャーナル")
        } footer: {
          Text("場所の自動記録と位置情報の項目はAIへ送信しません。電池への影響を抑えるため、駅の判定はおおよそです。カレンダーの予定は保存せず、表示のたびに読み込みます。")
        }

        Section {
          Toggle(isOn: Binding(get: { appLockEnabled }, set: { enabled in
            if enabled, let message = AppLockService.availabilityMessage() {
              appLockError = message
            } else {
              appLockEnabled = enabled
            }
          })) {
            SettingsLabel("Face IDでロック", icon: .faceidFill, color: Tint.privacy)
          }

          NavigationLink {
            PrivacyStorageView()
          } label: {
            SettingsLabel("データの保存先", icon: .lockShieldFill, color: Tint.privacy)
          }

          NavigationLink {
            StorageUsageView()
          } label: {
            SettingsLabel("保存容量", icon: .internaldriveFill, color: Tint.privacy, artwork: .settingsStorage)
          }

          LabeledContent {
            Text(model.cloudStorageStatus)
          } label: {
            SettingsLabel("クラウド保管", icon: .cloudFill, color: Tint.privacy)
          }

          NavigationLink {
            SettingsBackupView()
          } label: {
            SettingsLabel("バックアップ", icon: .externaldriveFill, color: Tint.privacy)
          }

          NavigationLink {
            ShareInboxView()
          } label: {
            SettingsLabel("共有からの取り込み", icon: .tray, color: Tint.privacy)
          }

          NavigationLink {
            RecentlyDeletedView()
          } label: {
            LabeledContent {
              Text(model.trashedRecords.isEmpty ? "なし" : "\(model.trashedRecords.count)件")
            } label: {
              SettingsLabel("最近削除した項目", icon: .trashFill, color: Tint.privacy)
            }
          }
        } header: {
          Text("プライバシーと保存")
        } footer: {
          Text("録音中はロックしません。")
        }

        Section {
          NavigationLink {
            SettingsNotesView()
          } label: {
            SettingsLabel("設定について", icon: .infoCircleFill, color: Tint.support)
          }
          LabeledContent {
            Text("準備中")
          } label: {
            SettingsLabel("ヘルプ", icon: .questionmarkCircleFill, color: Tint.support)
          }
          LabeledContent {
            Text("準備中")
          } label: {
            SettingsLabel("プライバシーポリシー", icon: .handRaisedFill, color: Tint.support)
          }
          LabeledContent {
            Text(Bundle.main.appVersion)
          } label: {
            SettingsLabel("バージョン", icon: .infoCircleFill, color: Tint.support)
          }
        } header: {
          Text("サポート")
        }

        Section("プロトタイプ") {
          NavigationLink {
            StateGalleryView()
          } label: {
            SettingsLabel("状態と復旧UIを確認", icon: .rectangleStackFill, color: Tint.prototype)
          }

          #if DEBUG
          NavigationLink {
            PerformanceLogView()
          } label: {
            SettingsLabel("計測と自己チェック（ビルド比較用）", icon: .stopwatchFill, color: Tint.prototype)
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
      .scrollContentBackground(.hidden)
      .background(Color(uiColor: .systemGroupedBackground))
      .contentMargins(.horizontal, 20, for: .scrollContent)
      .contentMargins(.top, 6, for: .scrollContent)
      .listSectionSpacing(24)
      .environment(\.defaultMinListRowHeight, 56)
      .textCase(nil)
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
      .navigationTitle(showsCloseButton ? "" : "設定")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        if showsCloseButton {
          ToolbarItem(placement: .confirmationAction) {
            ToolbarIconButton("閉じる", icon: .xmark) { dismiss() }
          }
        }
      }
      .sheet(isPresented: $isProfileEditorPresented) {
        ProfileEditorView()
      }
      .sheet(isPresented: $isPlanPresented) {
        PaywallView()
      }
      .sheet(isPresented: $isAuthPresented) {
        AuthView()
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
      .alert("アプリロックを設定できません", isPresented: Binding(
        get: { appLockError != nil }, set: { if !$0 { appLockError = nil } }
      )) {
        Button("OK", role: .cancel) { appLockError = nil }
      } message: {
        Text(appLockError ?? "")
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
    .environment(\.settingsIconStyle, .monochrome)
    .tint(Color.primary)
    .accessibilityIdentifier("settings")
  }

  private var profileSection: some View {
    Section {
      Button {
        isProfileEditorPresented = true
      } label: {
        VStack(spacing: 10) {
          ProfileAvatar(profile: model.profile, size: 80)
            .overlay(alignment: .bottomTrailing) {
              Image(icon: .pencil, size: 14)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: Circle())
                .overlay { Circle().stroke(Color(uiColor: .systemGroupedBackground), lineWidth: 2) }
            }

          VStack(spacing: 3) {
            Text(profileName)
              .font(.headline)
              .foregroundStyle(.primary)
          }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
        .padding(.bottom, 8)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .listRowInsets(EdgeInsets())
      .listRowBackground(Color.clear)
      .listRowSeparator(.hidden)
      .accessibilityLabel("プロフィール \(profileName)")
      .accessibilityHint("ミー文字・写真・名前を編集します")
    }
  }

  /// The credits left this month, as the server last said, or what the plan
  /// includes while no answer has come back yet.
  private var creditSummary: String {
    if let remaining = MemoraCreditMeter.shared.remaining { return "残り\(remaining)" }
    if let plan = model.effectivePlan { return "\(plan.monthlyCredits)/月" }
    return "なし"
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

/// One tile color per Settings section, so the rows of a section read as a group.
private enum Tint {
  static let account = Color.blue
  static let plan = Color.orange
  static let appearance = Color.indigo
  static let processing = Color.purple
  static let device = Color.green
  static let integrations = Color.teal
  static let journal = Color.red
  static let privacy = Color.cyan
  static let support = Color.gray
  static let prototype = Color.gray
}
