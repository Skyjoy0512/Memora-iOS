# Project UX Phase 1 — 実装と検証

2026-10-12。オーナーの「実装して」を受け、承認前レビューの一覧・詳細案を既存画面へ適用した。

## 実装

- ProjectsView / ProjectListRow: 大型カードから本文サイズの行へ変更。名前・記録件数・最新記録日だけを主表示とし、独立した44ptメニューを維持。名前順／最新記録順、最近使用優先を設定として保存。最近使用と残りのIDは排他的で重複しない。
- ProjectLayout / ProjectListOrder: 横16pt、最小72ptの可変行高と表示専用のソート。本文17pt・補助13ptはシステムフォント。アクセシビリティ文字サイズでは一覧見出しと並べ替えを縦配置。
- SpaceDetailView: 名前は既存ナビゲーションのLarge Title一つ。関連未完了タスク→最近の記録→資料を各3件から表示し、同じ画面内で全件展開／折りたたみ。全件表示では従来のカード／リストと並べ替え設定が使える。3件以下の記録はメニューから全件表示へ切り替えられる。
- ProjectRecordRow / ProjectDocumentRow: 装飾背景を持たない記録・資料の行。処理失敗等のMeetingStatusLabelは維持。
- 全内容が空の詳細は一つの簡潔な案内。録音／インポートは既存右端FABを利用。「既存記録を移動」は既存ProjectFilePickerSheetへ接続。
- 定型AI質問は「未決事項を質問」として詳細メニューに移動。元の質問文・AIQuestionView・.spaceスコープ・自動実行を維持。

## 再利用と保護

TaskRow、TaskEditView、MeetingCard、ProjectFilePickerSheet、BulkSpacePickerSheet、RenameSpaceSheet、AIQuestionView、SharedOwnerBadgeと既存のLibraryRouteを再利用。関連資料は既存MemoraDocument.spaceIDと.documentルートを使用する。

RootTabView / ProminentTabBar / QuickAIComposer / CaptureMenuPopover / MemoraGlass / BottomBarScrollBehavior / データモデル / 保存・録音・AI・共有ロジックは変更していない。3タブの順序はライブラリ・ジャーナル・Ask AI。ファイル／プロジェクト切り替えの位置も維持。

タスクは録音のmeetingIDを経由する既存条件のまま。直接task.spaceIDや架空の進捗を追加していない。資料本文はAIに送られない。資料閲覧中のAIスコープは既存のglobal、録音先はnilであり、親プロジェクトを暗黙に継承しない。

## 実施済み検証

- Bitrig iOS Simulatorビルド成功。既存のAppIntents metadata警告1件。
- ProjectListOrderChecks成功: 0／1／100件、自然な名前順、最新記録順、日時なし、同順位の安定性。
- RootNavigationChecks成功: 3タブ・旧ID復元・セグメント復元・録音先・AIスコープ。追加した資料閲覧時のglobal／録音先nilも成功。
- StandaloneRecordPrivacyChecks成功: 旧JSON、許可、継承、親の制約、孤立したリンク、位置情報除外。
- iPhone 18 Pro Maxシミュレーター: プロジェクト作成→名前変更→削除、検索一致／該当なし／終了、空状態、記録移動、関連タスク3件の表示、TaskEditViewを開いてキャンセル、記録詳細への遷移と戻る、1件でも全件カード表示→折りたたみ。
- 同シミュレーター: 詳細FABに正しい保存先名、録音開始→17秒の音声保存→同プロジェクトの件数増加を確認。文字起こしエンジンは利用不可の実エラーを表示し、サンプルを生成しなかった。
- 詳細→記録→詳細で質問欄の対象名が切り替わること、プロジェクト削除後の一覧ではglobalの入力欄となりFABに前の保存先が出ないことを確認。
- ジャーナルの最近使用したプロジェクトから詳細への遷移を確認。
- Light／Darkとアクセシビリティ文字サイズで詳細を目視確認。一覧は透明度を下げる・Reduce Motion・文字拡大も確認。設定は通常のlarge／lightへ戻した。VoiceOverはAXラベルの確認まで。
- 検証用プロジェクトを削除し、一時移動した既存「通話」を未分類へ戻した。既存2録音はファイル一覧に残る。新規テスト録音だけを最近削除した項目へ移動し、完全削除はしていない。既存タスクの内容・完了状態は変更していない。

## 未確認と制約

小さいiPhoneの実描画、100件の実スクロール、最近使用優先の多数データでの目視、4件以上の展開、所属資料の実データ表示、VoiceOverの読み上げ一巡は未確認。資料ルートと多数データソートはコード／自動チェックとビルド確認の範囲。

クラウド共有の実アカウント・権限、AIプロバイダーの実回答・履歴、音声インポート・オンライン会議の実接続、通知のOS配信、実機マイクとGlassのフレーム単位のアニメーションは今回の実機E2Eでは検証していない。既存機能を無効化したり、成功として報告したりしない。

GitHubへの新しいpushは行わない。ローカルの変更をコミットする。

## 追加依頼：ファイル一覧の行デザイン統一

オーナーの追加依頼により、LibraryViewのファイルカードもProjectRecordRowを再利用するLibraryRecordRowへ変更。余白・本文フォント・アイコン寸法を揃え、不透明なカード背景と大きな枠を除去し、ネイティブListの区切り線を表示する。共有記録も同じ行と所有者バッジを使用し、読み取り専用ルートは維持。

以前のカード／リストの保存値はそのまま引き継ぎ、ライブラリ内の表示名のみ「プレビュー付き／コンパクト」に変更する。前者は短い要約を2行表示、後者はタイトル・メタデータ中心。選択状態、長押し・スワイプ操作、既存card側のmatchedTransitionSourceを保持。MeetingCard自体とジャーナル・詳細のカードは変更しない。

## 追加依頼：一般的な画面タイトルの削除

LibraryViewとHomeViewの固定タイトル（ライブラリ／ジャーナル）を空にし、ルートをinline表示へ変更。検索・メニュー・作成ツールバーと主要スクロールビュー、GlassSegmentedPickerはそのまま。ProjectsViewの重複した「プロジェクト」見出しは件数だけに整理し、文字拡大時も件数と並べ替えだけを表示する。選択中の件数、検索結果、個別プロジェクト名／記録名、情報を分類するセクション見出しは維持する。

### 最終差分のビルドとプレビュー制約

ファイル行統一・一般タイトル削除を含む最新差分はBitrigが引き継いだiOS Simulatorビルドで成功。ログ: `2026-10-12T22-23-14-2caf8291.log`（BUILD SUCCEEDED、既存AppIntents metadata警告）。

その後のSimulator Useは `Simulator state is stale because project files changed` を繰り返し返した。再ビルド成功とターゲット再取得後も解消しないため、再試行を打ち切った。追加依頼のファイル行・タイトル削除後の最終スクリーンショット、複数選択、ファイル詳細への実操作回帰は未確認。先に記載したプロジェクト詳細の実操作結果と区別する。推測で確認済みにしない。
