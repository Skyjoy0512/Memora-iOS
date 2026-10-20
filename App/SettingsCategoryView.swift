import SwiftUI

/// Leaf settings keep their original bindings, permissions and confirmations.
struct SettingsCategoryView: View {
  @Environment(MemoraModel.self) private var model
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
  @State private var isPlanPresented = false
  @State private var isAuthPresented = false

  var category: SettingsCategory
  var closeSettings: () -> Void = {}

  var body: some View {
    Group {
      if category == .integrations {
        IntegrationsView()
      } else {
        Form {
          switch category {
          case .account: accountSections
          case .plan: planSections
          case .appearance: appearanceSections
          case .recording: recordingSections
          case .ai: aiSections
          case .journal: journalSections
          case .privacy: privacySections
          case .data: dataSections
          case .about: aboutSections
          case .diagnostics: diagnosticsSections
          case .integrations: EmptyView()
          }
        }
        .memoraSettingsPage(category.title)
      }
    }
      .onAppear { excludedPlaceCount = AutoLocationLogger.excludedPlaces.count }
      .onDisappear {
        // A permission request the person walked away from must not surface its
        // alert on another screen later.
        AutoLocationLogger.shared.discardPendingEnable()
      }
      .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
        excludedPlaceCount = AutoLocationLogger.excludedPlaces.count
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
          closeSettings()
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

    .tint(MemoraPalette.textPrimary)
  }

  private var accountSections: some View {
    Group {
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
                SettingsIcon(icon: .personCropCircleFill)
              }
            }

            Button {
              isSignOutConfirmationPresented = true
            } label: {
              SettingsLabel("サインアウト", icon: .rectanglePortraitAndArrowRight)
            }
          } else {
            Button {
              isAuthPresented = true
            } label: {
              LabeledContent {
                Text("このiPhoneのみ")
                  .foregroundStyle(.secondary)
              } label: {
                SettingsLabel("サインイン / 新規登録", icon: .personBadgeKey)
              }
            }
          }
        } header: {
          Text("アカウント")
        } footer: {
          Text("同期・アカウントは未接続です。このiPhoneだけで使えます。")
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
  }

  private var planSections: some View {
    Group {
        Section {
          Button {
            isPlanPresented = true
          } label: {
            LabeledContent {
              Text(model.planName)
                .foregroundStyle(.secondary)
            } label: {
              SettingsLabel("プラン", icon: .crownFill)
            }
          }

          NavigationLink {
            AICreditsView()
          } label: {
            LabeledContent {
              Text(creditSummary)
            } label: {
              SettingsLabel("AIクレジット", icon: .sparklesRectangleStack)
            }
          }

          NavigationLink {
            LicenseActivationView()
          } label: {
            LabeledContent {
              Text(model.activeLicense?.company ?? "未登録")
            } label: {
              SettingsLabel("法人ライセンス", icon: .building2Fill)
            }
          }

          if model.hasTeamPlan {
            NavigationLink {
              TeamSharesView()
            } label: {
              LabeledContent {
                Text(model.cloudSharing.receivedItems.isEmpty ? "なし" : "\(model.cloudSharing.receivedItems.count)件")
              } label: {
                SettingsLabel("チーム共有", icon: .person3Fill)
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
                SettingsLabel("チーム共有", icon: .person3Fill)
              }
            }
          }
        } header: {
          Text("プランと利用状況")
        } footer: {
          Text("購入は未接続です。プランの変更は端末の設定のみで、課金されません。")
        }


    }
  }

  private var appearanceSections: some View {
    Group {
        Section {
          Toggle(isOn: $prefersDarkAppearance) {
            SettingsLabel("ダークモード", icon: .moonFill)
          }
          Toggle(isOn: $hapticsEnabled) {
            SettingsLabel("触覚フィードバック", icon: .iphone)
          }
        } header: {
          Text("表示と操作")
        } footer: {
          Text("タップ・選択・操作完了を振動で知らせます。録音・音声入力・声の登録中は、音声に振動が入らないよう抑えます。")
        }


    }
  }

  private var recordingSections: some View {
    Group {
        Section("文字起こし") {
          NavigationLink { SpeechRecognitionSettingsView() } label: {
            SettingsValue(title: "文字起こし", value: "\(transcriptionEngine.label) · \(transcriptionLanguage.label)", icon: .waveform)
          }
        }
        Section("音声") {
          NavigationLink { VoiceProfileView() } label: { SettingsLabel("声のプロフィール", icon: .personWave2) }
          NavigationLink { SpeakerIdentificationSettingsView() } label: { SettingsLabel("話者識別", icon: .person2) }
        }
        Section("デバイス") {
          NavigationLink {
            ExternalRecorderSettingsView()
          } label: {
            LabeledContent {
              Text(model.omiPairingManager.state.shortLabel)
            } label: {
              SettingsLabel("外部レコーダー", icon: .dotRadiowavesLeftAndRightFill)
            }
          }
        }


    }
  }

  private var aiSections: some View {
    Group {
        Section("モデル") {
          NavigationLink { AISettingsView() } label: {
            SettingsValue(title: "AIモデル", value: model.aiEngine == .cloud ? model.aiProvider.label : model.aiEngine.label, icon: .sparkles)
          }
        }
        Section("要約") {
          NavigationLink { SummaryStyleSettingsView() } label: { SettingsLabel("要約スタイル", icon: .docText) }
          NavigationLink { SummaryTemplateMarketplaceView() } label: { SettingsLabel("要約テンプレート", icon: .docOnDoc) }
          NavigationLink { OccupationSelectionView() } label: {
            SettingsValue(title: "仕事・活動", value: model.occupationSummary, icon: .briefcase)
          }
        }
        Section("Ask AI") {
          NavigationLink { SkillsView() } label: { SettingsLabel("スキル", icon: .docRichtext) }
          NavigationLink { AIMemoryView() } label: {
            SettingsValue(title: "メモリ", value: model.isAIMemoryEnabled ? "\(model.aiMemories.count)件" : "オフ", icon: .brainHeadProfile)
          }
          NavigationLink { ResidentAgentsView() } label: {
            SettingsValue(title: "常駐エージェント", value: model.residentLLM == nil ? "BYOKのみ" : "\(model.residentAgents.filter(\.isEnabled).count)件オン", icon: .clockArrowCirclepath)
          }
        }
    }
  }

  private var journalSections: some View {
    Group {
        Section {
          Toggle(isOn: autoLifeLogBinding) {
            SettingsLabel("移動と滞在を自動で記録", icon: .locationFill)
          }

          NavigationLink {
            ExcludedPlacesView()
          } label: {
            LabeledContent {
              Text(excludedPlaceCount == 0 ? "なし" : "\(excludedPlaceCount)件")
            } label: {
              SettingsLabel("記録しない場所", icon: .mappinSlashFill)
            }
          }

          Toggle(isOn: calendarEventsBinding) {
            SettingsLabel("カレンダーの予定を表示", icon: .calendarFill)
          }

          NavigationLink {
            CalendarSelectionView()
          } label: {
            SettingsLabel("表示するカレンダー", icon: .calendarBadgeCheckmarkFill)
          }
          .disabled(!showCalendarEvents)
        } header: {
          Text("ジャーナル")
        } footer: {
          Text("場所の自動記録と位置情報の項目はAIへ送信しません。電池への影響を抑えるため、駅の判定はおおよそです。カレンダーの予定は保存せず、表示のたびに読み込みます。")
        }


    }
  }

  private var privacySections: some View {
    Group {
        Section {
          Toggle(isOn: Binding(get: { appLockEnabled }, set: { enabled in
            if enabled, let message = AppLockService.availabilityMessage() {
              appLockError = message
            } else {
              appLockEnabled = enabled
            }
          })) {
            SettingsLabel("Face IDでロック", icon: .faceidFill)
          }

          NavigationLink {
            PrivacyStorageView()
          } label: {
            SettingsLabel("データの保存先", icon: .lockShieldFill)
          }

        } footer: {
          Text("録音中はロックしません。")
        }

    }
  }

  private var dataSections: some View {
    Group {
        Section {
          NavigationLink {
            StorageUsageView()
          } label: {
            SettingsLabel("保存容量", icon: .internaldriveFill)
          }

          LabeledContent {
            Text(model.cloudStorageStatus)
          } label: {
            SettingsLabel("クラウド保管", icon: .cloudFill)
          }

          NavigationLink {
            SettingsBackupView()
          } label: {
            SettingsLabel("バックアップ", icon: .externaldriveFill)
          }

          NavigationLink {
            ShareInboxView()
          } label: {
            SettingsLabel("共有からの取り込み", icon: .tray)
          }

          NavigationLink {
            RecentlyDeletedView()
          } label: {
            LabeledContent {
              Text(model.trashedRecords.isEmpty ? "なし" : "\(model.trashedRecords.count)件")
            } label: {
              SettingsLabel("最近削除した項目", icon: .trashFill)
            }
          }
        } header: {
          Text("保存とバックアップ")
        }


    }
  }

  private var aboutSections: some View {
    Group {
        Section {
          NavigationLink {
            SettingsNotesView()
          } label: {
            SettingsLabel("設定について", icon: .infoCircleFill)
          }
          LabeledContent {
            Text("準備中")
          } label: {
            SettingsLabel("ヘルプ", icon: .questionmarkCircleFill)
          }
          LabeledContent {
            Text("準備中")
          } label: {
            SettingsLabel("プライバシーポリシー", icon: .handRaisedFill)
          }
          LabeledContent {
            Text(Bundle.main.appVersion)
          } label: {
            SettingsLabel("バージョン", icon: .infoCircleFill)
          }
        } header: {
          Text("サポート")
        }


    }
  }

  private var diagnosticsSections: some View {
    Group {
        Section("表示と動作") {
          NavigationLink {
            StateGalleryView()
          } label: {
            SettingsLabel("状態と復旧UIを確認", icon: .rectangleStackFill)
          }

          #if DEBUG
          NavigationLink {
            PerformanceLogView()
          } label: {
            SettingsLabel("計測と自己チェック（ビルド比較用）", icon: .stopwatchFill)
          }

          // Destructive resets only exist for development; a shipped build must
          // never offer to replace or empty someone's records.
          Button("初回体験をもう一度見る", icon: .arrowCounterclockwise) {
            model.replayOnboarding()
            closeSettings()
          }

          Button("デモデータを入れ直す（今の内容を置き換えます）", icon: .arrowClockwise) {
            model.loadSampleContent()
          }

          Button("すべて空にしてEmptyを確認", icon: .tray, role: .destructive) {
            isDeleteConfirmationPresented = true
          }
          #endif
        }


    }
  }

  /// The credits left this month, as the server last said, or what the plan
  /// includes while no answer has come back yet.
  private var creditSummary: String {
    if let remaining = MemoraCreditMeter.shared.remaining { return "残り\(remaining)" }
    if let plan = model.effectivePlan { return "\(plan.monthlyCredits)/月" }
    return "なし"
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
