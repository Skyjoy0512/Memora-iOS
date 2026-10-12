# 単独記録とクラウドAsk AIの許可

## ジャーナルとタスク
- ジャーナル詳細の「その他 → プライバシーと外部送信」、タスク編集の同名項目から設定する。分類の変更時は送信許可をオフに戻し、クラウドAI利用と常駐AIアクセスを個別に明示する。
- 新規/旧版の単独ジャーナル・タスクは未判定・未許可。Meetingと同じSQLite JSON/バックアップ経路に追加し、本文や音声を変更しない。
- 関連タスクは、個別設定がない場合だけ元の録音の許可を引き継ぐ。個別設定は元の録音の制限を上書きしない。元の録音が欠落/未許可なら拒否する。元の会議の変更/解除時は個別の外部許可を失効させる。
- ジャーナルは関連録音の許可に加えて、そのメモ自身の許可が必要。自動位置ログ/移動/滞在と場所の記録は許可設定にかかわらずAI読み取り不可。送信するのは手動記録のタイトル・本文・日時だけで、座標・写真ファイル・場所フィールドは送信しない。
- 常駐とクラウドの検索/本文/タスク/期間レビューに適用。Files/Projectsスコープへ独立メモ・独立タスクを混ぜない。Webhook/チームの単独記録配信は未実装なので設定を出さない。関連タスクは既存の録音Webhook・チーム共有、関連メモは既存の手動チーム用パッケージに含める許可を個別に設定できる。
- Webhook・チームにも子記録の許可を適用し、親だけの許可で個別に拒否したタスクを配信しない。送信前の再検証でも取消を確認。パッケージに入れる関連メモから座標・場所フィールドを除き、通常の個人用バックアップの原本は変更しない。

## 検証
StandaloneRecordPrivacyChecks: 単独未設定、明示許可、既存関連タスクの継承、親の許可取消、孤立したリンク、機密区分の下限、旧タスクJSON、位置情報の除外。ジャーナルJSONの保存/旧形式はアプリSelfChecksへ追加。

2026-10-12: 純SwiftのStandaloneRecordPrivacyChecks/AIConversationProvenanceChecks/RecordPrivacyChecks/JournalActivityDaysChecks成功。Bitrig Debugビルド成功（既存警告5件）。シミュレーターでCloud conversation provenance/Standalone journal privacy codec/旧要約・ストア移行の自己チェック成功、タスクの許可画面・未判定の全送信オフ・キャンセルを確認した。実データの許可・本文を変更せず、有料API呼び出しは実行していない。

クラウドAPIの追加呼び出しや声の自動本人確定は行わない。実際の送信E2Eと実機は別途確認する。

## 会話履歴の再利用
- 新規のクラウドエージェントの入力/読み取りツールで、録音・メモ・タスクの種類付きIDと内容のSHA-256を追跡し、AI履歴へ保存する。会話を続ける際も出典・内容・現在の許可・ワークスペース・明示メモリの状態を再検証する。
- 元の記録の編集/削除/許可取消、メモリの変更、ワークスペース変更後は古い会話を自動で再送しない。履歴本文の閲覧・端末内での利用は維持する。
- 新しい会話へ過去の会話を取り込んだ場合、その出典も引き継ぐ。直近3往復・3000文字・参照256件まで。上限や追跡不能なツールを含む会話は再利用しない。
- Gmail・外部MCP・変更ツール・人物/プロジェクト情報など、完全な出典を追跡できない経路は再利用不可にする。旧履歴・常駐AI・端末内AI・添付を使う単発クラウド回答には出典を推測追加しない。設定の履歴から続けられるのは新しい追跡可能な会話だけ。
- 実行中も外部利用許可・明示メモリ・ワークスペース変更を確認して継続を停止する。送信開始済みの内容を回収できるわけではない。
- 利用者が承認した新規タスクの追加だけで処理を誤停止しないよう、実行中の監視は既存/読み取った対象の許可取消を確認する。承認待ちの間に許可が取り消された場合も、承認を適用しない。
- 分担調査の子エージェントも次のAPI呼び出し前/応答後に同じ許可を確認する。
- クラウドで追跡できない履歴を開いた場合は、本文を残したまま再送しない理由を表示する。
- SHA-256は編集検出であり認証/真正性の保証ではない。音声・写真・声特徴量は履歴の出典メタデータに含めない。新規のモデル/API呼び出しは無く、許可した過去会話の文字数分だけ入力トークンは増える。

## 未検証・今後
実LLM・Webhook・CloudKitの送信E2E、許可取消と並列実行の実機ストレスは未検証。Gmail/MCPなど外部データの履歴出典は未対応。メモ/タスクへの回答内の直接引用リンクUI、単独記録を独立配信するWebhook/チーム機能は未追加。

## 主な変更ファイル
- データ/許可: `LifeLogEntry.swift`, `MemoraTask.swift`, `RecordPrivacy.swift`, `RecordAccessPolicy.swift`, `RecordPrivacyTarget.swift`, `MemoraModel+RecordPrivacy.swift`, `MemoraModel+Tasks.swift`。
- UI: `RecordPrivacySettingsView.swift`, `LifeLogEntryDetailView.swift`, `TaskEditView.swift`。
- AI: `AIConversationEntry.swift`, `AIChatMessage.swift`, `AIConversationProvenance.swift`, `AIRecordReference.swift`, `AIRecordFingerprint.swift`, `MemoraModel+AIProvenance.swift`, `MemoraModel+AutomaticRecordTools.swift`, `MemoraModel+Agent.swift`, `MemoraModel+AgentTools.swift`, `MemoraModel+AgentResearch.swift`, `MemoraModel+AI.swift`, `MemoraModel+Memory.swift`。
- 配信/検証: `MemoraModel+Webhooks.swift`, `MemoraModel+Backup.swift`, `SelfChecks.swift`, `tools/checks/StandaloneRecordPrivacyChecks.swift`, `tools/checks/AIConversationProvenanceChecks.swift`。
