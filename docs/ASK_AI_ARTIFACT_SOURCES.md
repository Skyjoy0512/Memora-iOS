# 資料・メールの出典引き継ぎ

2026-10-17。前回の人物プライバシー実装（`3f71064`）からの継続差分。

## 実装

- `ArtifactProvenance` を資料とメール下書きに任意フィールドとして追加。ワークスペース、
  元メッセージID、参照日時、種類付き記録IDと指紋、プロジェクト資料ID・所属・指紋を保存。
  人物・会議・タスク・ジャーナルに同じUUIDがあっても区別する。本文・人物メモの複製はしない。
- 通常のクラウド参照に加え、端末内の人物ツールと対象記録の読み取り時にも出典を記録。
  元記録の読取時の値を保持し、保存時に現在の内容で指紋を書き換えない。
- 一般の回答を資料へ保存する操作、`create_document` / `create_slides`、`draft_email` へ連携。
  資料本文・メール本文を本人が編集しても生成時の出典を維持する。
- 資料とメールの既存画面内に「参照した情報」を集約。人物・会議・タスク・ジャーナル・
  プロジェクト資料に同じ行部品を使い、元の詳細画面を開く。
  削除した情報も行を残して「見つかりません」と表示する。名前や本文は保存した出典から再表示しない。
- 指紋の変化と、現在の外部AIへの送信可否を別々に表示。外部送信不可でも本人は端末内の
  元情報を開ける。別ワークスペース、復元中、保存先保護中には出典名と遷移をブロックする。
- 文書生成は承認後とファイル保存直前に再確認。メール下書きは承認後にワークスペース、
  メッセージ存続、キャンセル、@指定、人物範囲、元情報の内容、クラウド許可を再確認して保存する。
  メールは端末内の下書きであり、実送信・Gmail下書きAPIは追加していない。

## 主な変更ファイル

| 範囲 | ファイル |
| --- | --- |
| 出典モデル | `ArtifactProvenance`, `ArtifactProjectSourceReference`, `ArtifactSourceTarget`, `ArtifactSourceRow`, `AIRecordReference`, `RecordPrivacyTarget` |
| 永続化 | `MemoraDocument`, `MailDraft`, `AIChatMessage`, `AIConversationSnapshot`, `BackupPackage` |
| 収集・保存 | `MemoraModel+AIProvenance`, `+ArtifactProvenance`, `+Documents`, `+MailDrafts`, `+MailDraftTool`, `+AgentTools`, `+AgentSources`, `+PersonTools`, `+AutomaticRecordTools`, `+Agent`, `+AI` |
| 表示・遷移 | `ArtifactSourcesView`, `ArtifactSourceLink`, `ArtifactSourceDetailView`, `DocumentDetailView`, `MailDraftSheet` |
| 架空データ | `ArtifactSourcesExampleView`, `StateGalleryView` (Debugのみ) |
| 検証 | `ArtifactProvenanceChecks`, `AIConversationSnapshotChecks`, `BackupRestoreChecks`, `AgentSourceChecks`, `PersonFixtureModel`, 対応する既存runnerと新しい `run-artifact-provenance-checks.sh` |

## 保存・互換性・権限

保存先は既存SQLiteの資料・下書きと会話resume document。旧データは出典フィールドなしで
読み込める。以前の会議ID・プロジェクト資料IDはリンクとして残すが「生成時点の内容は未記録」と
表示する。現時点の内容を生成時の根拠として補完しない。

出典は記録256件・プロジェクト資料32件まで。重複、指紋形式、日時、ワークスペース文字数を検証。
不正な新しい出典は保存・バックアップ読取時に拒否し、表示時にも元情報を解決しない。
バックアップは削除済み出典のIDを保持できる。IDの存在を復元の必須条件にはしない。

保存された出典は実行権限ではない。`AgentSourceReference` は引き続き実行中だけの認可情報で、
保存用には別の型へ値をコピーする。会話復元後にツール権限・UI操作権限・クラウド送信許可を復活させない。
写真・連絡先IDは人物のAI出典指紋の対象外。既存の人物プライバシー規則を維持する。

## 限界

表示するのはAIへ渡した参照文脈であり、本文の各文との対応を検証した引用ではない。
検索候補や関連会話の根拠も含む。外部ツール・添付・Web根拠はそれぞれ既存の経路があり、
今回の型付き出典一覧ですべてを網羅したと表示しない。端末内経路の一部と旧会話は不完全な出典として扱う。
既存の回答中の【資料n】引用は会議中心のまま。タスク・人物・ジャーナルの文中引用は次の作業。

プライバシー変更で既に作成した本文を自動削除・再生成しない。元情報への外部送信許可が失効しても、
本人が作成済みの下書きや資料を共有する操作とは区別する。
チームの記録バックエンドは未接続のままで、個人の出典をチーム画面へ解決しない。

## 検証

- `run-artifact-provenance-checks.sh`: 本番の出典処理、資料保存/編集、メール下書きツール・保存処理と
  隔離SQLiteを使用。同じUUIDの型別解決、変更/削除/許可失効、スコープ切替、保存失敗、旧形式、
  保存後の再読込、承認待ち中の変更/停止を検査。モデル状態、承認UI、@判定入口、資料本文ビルダー、
  通知/メディアとプロジェクト資料のアクセス判定入口はfixture。LLM/API通信はない。
- 会話snapshot検証: 任意出典の保持と旧形式読込、他ワークスペース・重複の拒否、権限の非復元。
- バックアップ検証: 本番package/restoreとSQLiteに新しい出典を含め、資料・メールの再読込、
  不正な重複とワークスペース不一致の拒否、既存のrollback/cancel/旧形式復元を確認。
- Office出力検証: 既存DOCX/PPTX生成・再読込と会社テンプレートPoCを再利用。最終Office描画は未検証。

ビルドと画面確認の最終結果は `ASK_AI_NEXT_VALIDATION.json` に記録する。
Debugの既存「状態と復旧UI」には架空の出典行を追加。実ユーザーの記録を書き換えずに表示を確認できる。

## 残件

- P0: 実BYOKまたは接続モックを通したA〜E全体と、クラウド送信中の失効・停止の統合確認。
  実機VoiceOver、長文/大量データ/メモリ/電力、復元UIでの確認。
- P1: 回答本文の型付き引用、引用文と根拠の一致検証、人物サマリー品質と確認付き記憶更新、
  複雑な会社書式のOffice描画、高忠実度編集、Gmail Draftsの権限分離と接続。
- P2: 日本語Embedding/Hybrid検索の実測と人物・プロジェクトの@指定。

第三者ライブラリ、常時サーバー、有料API、課金設定、本番デプロイ、認証設定の追加はない。
