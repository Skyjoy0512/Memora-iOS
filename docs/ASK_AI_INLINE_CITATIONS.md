# 回答本文の型付き出典とモック統合検証

2026-10-17。`4d5732c` からの継続実装。

## 実装した範囲

既存の `【資料n】` を維持し、人物・タスク・ジャーナル・会議・プロジェクト資料を種類とUUIDで
指定する出典マーカーを追加した。モデルには道具が返した種類・IDだけを使うよう指示し、
アプリ側も回答の出典情報に含まれる対象だけをリンクにする。

| マーカー | 対象 | 保存するリンク |
| --- | --- | --- |
| `【人物:UUID】` | 人物 | `memora://source/person/UUID` |
| `【タスク:UUID】` | タスク | `memora://source/task/UUID` |
| `【メモ:UUID】` | ジャーナル | `memora://source/journal/UUID` |
| `【記録:UUID】` | 会議 | `memora://source/meeting/UUID` |
| `【資料:UUID】` | プロジェクト資料 | `memora://source/file/UUID` |

- 参照していないID、種類の取り違え、不正なIDはリンクにせずマーカーを除く。
  ストリーミング中の閉じていないマーカーも末尾から除き、内部IDを途中表示しない。
- URLは正規形だけを認め、query/fragment/user/port/余分なパス/不正なエンコードを拒否する。
  本文中に直接書かれた内部URLも、タップ時に回答または資料の出典集合と再照合する。
- 人物・タスク・メモ・会議・資料の既存詳細画面を開く。個人ワークスペース以外、復元中、
  保存先保護中は解決しない。削除済みは詳細側で見つからない状態になる。
- 既存会議引用の番号を付け直さず、未許可の引用だけを除く。会議名のMarkdown特殊文字をエスケープする。
- 回答を資料に保存するときも型付きリンクと出典情報を保持し、JSON/SQLite再読込後も同じ種類・IDへ解決する。
  古い会議リンクしかない資料は個人端末内で引き続き開ける。旧データに人物・タスクの権限を補わない。
- 既存の `memora` URL scheme を使う。外部から明示的に開いた出典リンクも個人端末内の表示だけを行い、
  AI読取許可・UI変更権限・ツール実行権限を作らない。ワークスペース変更時は出典シートを解除する。
- メールの件名・本文から引用マーカーを除き、内部IDを通常のメール文面に混入させない。
  元の人物・タスク・メモは下書きの出典メタデータとして別に保存する。宛先不明は空欄、状態は下書きのまま。

## 主な変更ファイル

- `AnswerSourceCitation` / `AnswerCitations`: 型、マーカー、厳密なURL解析、引用の変換・除去。
- `MemoraModel+AnswerCitations`: 回答・保存資料の出典照合と明示的な外部リンクからのローカル表示。
- `AIMessageView`, `DocumentDetailView`, `ArtifactSourceDetailView`, `RootTabView`: 本文から元情報への遷移。
- `AIAnswerDocumentBuilder`, `MemoraModel+Documents`, `+AgentTools`: 実際の資料保存経路への引き継ぎ。
- `MemoraModel+Agent`, `+PersonTools`, `+AutomaticRecordTools`, `+AgentSources`: 道具結果とモデルへの出典形式の提供。
- `MemoraModel+MailDraftTool`, `+Import`, `+Conversation`, `MemoraModel`: 文面の整形、URL入口、解除、保存状態。
- `InlineCitationExampleView`, `ArtifactSourcesExampleView`: 実記録を使わないDebug表示確認。
- `InlineCitationChecks`, `ArtifactProvenanceChecks`, `PersonFixtureModel` と既存runner: 回帰・モック統合検証。

## 検証方法

`run-inline-citation-checks.sh` は本番の型付き引用・URL解析、既存会議引用、資料本文ビルダー、
会話snapshotを使用する。同じUUIDを5種類に使い、他ID/種類不一致/URL変形/途中マーカー/ラベルの
特殊文字/保存後のリンクを検査する。5,000個のマーカーも処理するが、これは実機性能の証明ではない。

`run-artifact-provenance-checks.sh` は本番モデルの出典照合と保存処理を隔離SQLiteで検証する。
これまでfixtureだった資料本文ビルダーも本番コードを使用するよう変更した。

追加したモックシナリオは次の順で実行する。

1. 同名人物2名のうち、明示した人物IDで本番 `read_person` を呼ぶ。
2. 人物に明示的に関連付けたタスク・メモと、それぞれのマーカーを取得する。
3. 本番 `AgentConversationLoop` が返却結果を受け取り、本番 `draft_email` で下書きを保存する。
4. 型付きマーカー付きの回答を本番ビルダーで資料へ保存する。
5. SQLiteを再読込し、本文リンク・出典メタデータ・宛先空欄・下書き状態を検査する。
6. 次のモデル応答待ちで人物のクラウド許可を失効し、応答と追加の下書きを採用しないことを確認する。

モデル応答と承認UI、registry入口、通知/メディア、プロジェクト資料アクセス判定入口はモック。
人物・タスク・ジャーナルの関連/個別権限、会話ループ、出典照合、資料/メールの保存、SQLiteは本番コード。
実BYOK接続や全サービスを通したA〜EのE2Eが完了したことにはしない。実ユーザーの記録・APIキーは使わない。

## 限界と残件

- リンクは「その回答で参照した対象」を表す。本文の各文や引用文が根拠と一致するという品質保証ではない。
  保存後に元情報が変わることもあり、出典欄の指紋比較・送信可否表示を引き続き利用する。
- 本文の直接URLを一般に除去するMarkdownサニタイザーは追加していない。内部URLを開く入口で対象を照合する。
- 会議の発言抜粋・再生位置、Web引用、既存の外部リンクはそれぞれの既存経路を維持する。
- DOCX/PPTX/PDF内でのリンクの最終描画・クリック可能性は未検証。今回保証するのはMemora内と保存Markdownの解決。
- P0: 本物の接続または通信レベルのモックでA〜E全体、実機VoiceOver/大量データ/停止と復元UIを確認する。
- P1: 記述と根拠の一致検証、人物サマリー品質、確認付き長期記憶更新、複雑なOffice書式とGmail Drafts OAuth。
- P2: 日本語Hybrid検索の実測と人物・プロジェクトの@指定。

新しい有料API、サーバー、認証・課金設定、外部送信、実メール送信は行っていない。
最終ビルド・UI・検証結果は `ASK_AI_NEXT_VALIDATION.json` に記録する。
