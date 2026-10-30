# UI/UX改善の実装と検証 — 2026-10-30

承認された18項目を3段階で実装した。対象は保存・編集保護、日常の操作、資料・写真。iOS 26の既存APIを使用し、Project.jsonと保存済みデータの形式は変更していない。

## 実装した項目

| 番号 | 変更 | 主な実装 |
|---|---|---|
| 1 | AIメモリがバックアップに含まれることを表示。その他の同梱データと除外項目も実際のManifestに合わせた | SettingsBackupView |
| 2 | タスクの作成・編集、人物、ジャーナル編集、要約テンプレート、登録モデル、資料の編集に下書きと破棄確認を追加 | EditorDraftProtection / EditorDraftEnvelope / 各編集画面 |
| 3 | 要約テンプレートは候補を永続化してから公開し、成功時だけ編集を閉じる | MemoraModel+Templates |
| 4 | 資料削除はBoolを返し、失敗時は一覧・詳細で通知。詳細画面は閉じない | MemoraModel+Documents / DocumentsView / DocumentDetailView |
| 5 | 実開始日時からの経過時間を小さなTimelineViewで表示。ラベル変更で開始時刻をリセットしない | WorkingStatus / ConversationStatusLine |
| 6 | ライブラリ検索中は一致する添付資料を全件表示。通常時の先頭3件は維持 | LibraryView |
| 7 | 再生・スキップ、取り消し、写真削除、人物の写真変更の実ラベル内に44ptのタップ範囲を確保 | MeetingPlaybackBar / UndoToast / MeetingNotesContent / PeopleManagerSheet |
| 8 | 週報の作成結果を保存成功・記録なし・失敗で区別。再作成は永続化成功後に公開 | WeeklyReviewResult / MemoraModel+WeeklyReview |
| 9 | ライブラリ・プロジェクト・資料・人物の選択表示の重複を解消 | FileSidebarView |
| 10 | AI設定のタイトルを「AIモデル」に統一。自動選択の説明を実装に合わせ、各候補の利用状態を表示 | AISettingsView / AIEngine |
| 11 | 品質の重要度別件数と最初の要修正事項を常時表示。各指摘から該当スライドの編集へ移動 | PresentationQualityView / PresentationEditorView |
| 12 | 決定の内部sourceID表示を出典名とリンクに変更。保存された根拠を権限として使わず、表示時・遷移時に再検査 | ArtifactSourceTarget+Presentation / PresentationQualityView |
| 13 | 要約画像をタップして拡大。生成・再生成は可視メニューから既存の確認画面へ進む | MeetingSummaryPosterEntry |
| 14 | 外観をシステム・ライト・ダークの3択に。旧trueはダーク、旧falseはシステムへ移行 | AppearancePreference / ContentView / SettingsCategoryView |
| 15 | 資料・人物・ジャーナル・履歴・共有などの表示日時を日本語ロケールで統一 | MemoraFormat / 各表示画面 |
| 16 | 拡大・移動だけの変更でも写真リセットを有効化。最大文字サイズに合わせ形選択をメニューへ、操作を縦配置へ変更。スクロールと読み上げ用の拡大・移動操作を追加 | PhotoEditorView |
| 17 | 会議ノート、人物、ジャーナル作成、プロフィールの写真読み込みに進行表示・失敗通知・再試行を追加。取消と古い選択・ワークスペースの結果を反映しない | PhotoSelectionLoader / 各利用画面 |
| 18 | タスク名を含む完了操作、写真の順番、回答の出典件数をアクセシビリティラベルに含める | TaskRow / MeetingNotesContent / AIReplyActionsRow |

下書きはSQLiteのDraftStoreを使用する。ワークスペースと対象ごとのキーで分離し、編集開始時の値・フィールド集合が一致した下書きだけ復元する。未保存の入力だけを保存し、保存済みの記録へ自動反映しない。キー・秘密情報は含めない。保存成功または明示的な破棄で消去する。

週報の更新は同じIDと個人の追記を維持する。生成部分を本人が全面的に編集した場合は上書きしない。自動作成では空週を静かに扱い、手動作成では空週と保存失敗を区別する。

## 検査と証拠

- `python3 tools/checks/run-editor-recovery-checks.py`: 日本語下書きの再読込、変更された元データ・不完全なフィールドの拒否、週報の作成・更新失敗と再試行、追記・IDの保持、旧外観設定の移行を検査した。
- `bash tools/checks/run-artifact-operation-checks.sh`: 実SQLiteのABORTで資料の追加・更新・削除に成功を返さず、メモリと再読込結果が変更されないことを確認。出典IDの不正形式・未対応種別を拒否し、既存の削除・権限・ワークスペース検査も通過した。
- `bash tools/checks/run-design-refresh-checks.sh`: デザイン・Lucide・設定・待機表示・モーション・出典・コンポーザー・エージェント予算等の既存検査を通過した。経過時間と外観の契約テストは承認された仕様へ更新した。
- `bash tools/checks/run-summary-reading-checks.sh`: 要約の読み取り・編集・SQLite失敗・取消・テンプレート・関係抽出・図解生成の検査を通過した。実モデルの生成品質検査ではない。
- `bash tools/checks/run-backup-restore-checks.sh`: 新旧パッケージ、メタデータ・ファイルの往復、破損・危険な参照・ロールバック・取消・復元後の再読込を通過した。
- 各段階で `bitrig preview -platform iOS` によるビルド・起動を実施した。既存のMapKit・OAuth等の非推奨警告11件は残る。
- iPhone 18 Pro Maxのプレビューで、人物編集の破棄確認と編集継続を操作した。未保存の日本語テキストを残してプレビューを再起動し、同じ人物の編集で復元されることを確認。その後、検査用下書きを破棄し、保存済みの人物名を維持した。
- プロジェクトの単独選択表示、外観の3択、人物一覧の日付表示を確認した。
- 保存・通信しない架空の写真で、移動だけの変更後にリセットが有効になることを確認した。最大文字サイズで見つけた形選択・ボタンの崩れを修正し、再度の画面確認で横のはみ出しがなく、下端の調整項目までスクロールできることを確認した。写真ライブラリの実通信失敗・iCloud上の写真の再試行は未実施。
- 保存しない架空資料で、折りたたみ前の「要修正1件・要確認1件」と対象メッセージを確認した。対象資料と初期ルートはPresentationEditRequestで一緒に渡し、初期パスはNavigationStackの状態初期化で確定する。最終ビルドで、指摘から先頭スライド（b01・空のタイトル）の入力欄へ直接移動することを確認した。Debugの表示検証は保存済み資料や外部AIを変更しない。

## 追加確認で残った課題・検証の境界

1. **長文PDFの改ページと生成中の応答性**: DocumentPDFは縦長の本文を固定高さで切る既存実装であり、段落・表の境界へ改ページを合わせる保証がない。生成もMainActor上で同期的に進む。今回の18項目では日時以外を変更していない。ブロック・表の行単位のページ構成と、進捗・取消・長文実測を別途行う必要がある。
2. **戻るジェスチャー**: 通常の戻るボタンは操作した。カスタム戻る画面の端スワイプはシミュレータ操作が行選択になり、可否を判定できなかった。既存の`.navigationBarBackButtonHidden(true)`を広範囲に置換していない。実機で確認が必要。
3. **画面サイズと向き**: 最大Dynamic Typeで写真編集の表示を検査した。プロジェクトは縦向きのみを宣言しているため、横向きへの設定操作ではアプリは回転しなかった。横向き対応を追加したとは扱わない。小さいiPhone全機種での検査は未実施。
4. **入力・読み上げ・外部出力**: 日本語テキストの入力・復元とAXラベルの確認は行ったが、ライブIMEの未確定文字、VoiceOverの実際の発声・全操作、実機・Officeの最終描画、共有先への受け渡しは未検証。クラウド接続、購入、チーム同期など既知の未接続サービスの実装は含まない。

既存のサイドメニュー、右上の作成メニュー、Ask AIコンポーザー、録音・文字起こし、承認・予算・参照権限の境界は維持する。Lucideの既存ラッパーを使用し、保存済みアイコン名は変更していない。

## 画面の証拠

- [資料の品質概要](uiux-2026-10/presentation-quality.png)
- [指摘から直接開いたスライド編集](uiux-2026-10/presentation-issue-editor.png)
- [写真編集・最大Dynamic Type](uiux-2026-10/photo-large-text.png)

最終プレビュービルド: `2026-10-30T19-51-44-13dae5b8.log`（success、既存警告11件）。プレビューの`SelfCheck failed`ログは0件。
