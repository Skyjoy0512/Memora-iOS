# 適応型構造化要約 — 実装と検証報告

対象基準: `342094666b366f5420bfe09d48f478ba08ea30ea`。開始時のmain/originも同じコミット。2026-11-14。

## 実装した変更

既存の `content.adaptive` と `MeetingSummarizer` を共用し、理解・抽出・構成・表示の責務を分離した。録音、外部音声/動画/字幕、Web/PDF/Office/テキスト/ノート、プロジェクト資料は、取得済みの原文だけを同じ要約経路へ渡す。ジャーナルの事実ベースのローカルrecapは維持する。

- 55市場テンプレートと4基本テンプレートを保持し、それぞれのfocus/sectionsを用途別の抽出プロファイルにした。ID、追加状態、既定設定を維持。候補は最大8、選択する用途は最大3。全55定義を毎回送らない。[全プロファイル](PROFILES.md)。
- 通常は内容に応じたタイトル・話題・文章を構成する。空欄補完、最低見出し数、担当/期限の「未定」補完を撤廃。カスタムの明示固定形式は保持する。既存の記録タイトルは本人の編集意図を推測せず保持する。
- 記録のタイトルが空の場合は、本文の先頭H1を表示名として使う。元のtitle値は変更せず、空でない手動/カレンダーのタイトルを上書きしない。共有とNotionも同じ表示名にそろえる。
- 生成時だけ構造を検査し、空見出し・空表・空チェックリスト・プレースホルダーだけの節・完全一致の重複節・余分な区切りを除く。明示的な保留や「問題なしと確認した」は残す。保存済み/編集済み本文を清掃しない。
- 通常の事実の重複削減では、タスク名用の大小文字/全角変換や部分一致を使わない。異なる識別子、正負の金額、否定/当初案、リンク先を保持する。
- 既存履歴 `TemplateSummary` を任意の `SummaryKnowledge` で拡張。confirmed/proposed/pending/notMentioned/uncertain/notApplicable、話題/事実ID、関連事実、検証済み引用を保持する。本文の見出しだけを新しい恒久参照キーにしない。
- source fingerprint・segment ID・引用を照合する。原文変更で失効し、音声削除だけなら文字起こしへ移動できる。架空の引用や不正IDは除外し要確認へ落とす。未取得ページ番号は採用しない。
- 本文を主表示にし、下部への要点/決定/未決の無条件な再掲を解消。その他→抽出情報を確認で確認・編集・既存タスク操作に到達できる。未言及は補助画面だけに表示する。
- 抽出編集は新しい履歴を作り、本人の編集と明示する。変更した主張へ生成時の引用を流用しない。本文・原文・既存タスクは自動変更しない。再生成でも本人の抽出編集・構造化リスト・タスクの完了/担当/メモを保護する。
- AskAIは関連する現在の抽出を予算内で参照し、本文と同じ完全な記述を減らす。要約の抜粋だけでなく原文検索を維持。プロジェクト検索にも既存のACL/原文再検証を維持する。複数用途で選ばれた機微プロファイルにも既存のprivacy保護を適用する。
- PDF・Notion・共有は本文と完全一致する項目の再掲を減らし、タスクを「現在の状態」として表示する。Webhookの送信スキーマ、権限、承認や自動送信先を増やさない。
- Markdownの表を横スクロールで表示し、本文とセル編集で共用。Dynamic Type時の字下げ/列幅に上限を設ける。ナビゲーション、Liquid Glass、下部AskAI、FAB構成は維持する。

UI検証で、タスク追加が画面へ反映されない不具合、共有の初回payload欠落、履歴復元の確認ダイアログが開かない不具合を再現・修正した。共有は表示IDとpayloadを同時に設定し、復元ダイアログは現在表示中の詳細画面が所有する。復元の保存失敗では成功通知を出さず、現在の要約を保持して失敗を通知する。

## 正本・互換性

原文はTranscriptSegment/資料ファイル、本文と保存済みリストはMeeting、タスクの現在状態はMemoraTask、生成時/編集時のスナップショットはTemplateSummaryが持つ。抽出を新しい独立した無制限の永続化ストアへ複製しない。

既存SQLiteを再作成せず、任意Codableフィールドとして追加。旧履歴や一部の壊れた抽出を読み込める。起動時の一括再要約・本文書換えは行わない。要約の確定は既存の記録/タスク/job同時トランザクションを維持し、途中ストリームは保存しない。処理中の編集・削除・権限/ワークスペース変更による失効も維持する。

本文と抽出が一致しなくなれば古い抽出と明示し、最新の原文事実として検索へ自動投入しない。本人の抽出編集を残した再生成も要確認として扱う。自動的な意味の同期や競合解決を保証する機能ではない。

## 同じ入力の比較と測定範囲

[7用途の変更前後](COMPARISON.md)に、短時間会議・定例・商談・ブレスト・日常・YouTube・長時間会議を収録。[全35ケースの対応](COVERAGE.md)、[測定JSON](fixture-metrics.json)。

**これは同じ手作業の抽出fixtureを新旧Swift builderへ渡した比較である。LLMが同じ原文から抽出した生成結果の比較ではない。** 変更後だけ都合のよいモデル出力を選んだものでもない。

| 指標 | 変更前 | 変更後 | 範囲 |
| --- | ---: | ---: | --- |
| 期待事実の保持 | 53/57 (93.0%) | 57/57 (100%) | 27内容fixture、builderで保持した文字列 |
| プレースホルダーだけの節 | 64 | 0 | 同じ27件 |
| 空見出し | 構造fixtureで再現 | 0 | 生成時清掃の専用fixtureと27件 |
| 推定入力トークン平均 | 4,214.5 | 3,365.7 | 長時間ケースを除く26件、TokenEstimate |
| 推定Markdown出力トークン平均 | 148.1 | 53.9 | 同上。抽出JSONの出力を含まない |
| 実LLM呼出し | 0 | 0 | 比較検証ではAPIを呼ばない |

入力推定は各fixtureで指定した単一用途のプロンプトを対象とする。おまかせの複数候補の入力消費をこの平均で評価していない。新しい知識JSONの出力量も出力推定に含まれず、実料金がこの比率で下がることを意味しない。約74,000文字の長時間fixtureは入力推定を通常平均に混ぜない。builder実行はホスト上でミリ秒未満〜数msであり、実モデル・実端末の処理時間ではない。

決定/アクションのモデル抽出精度、原文にない担当/数値/決定の生成件数、意味的重複、実モデルJSON成功率、根拠参照有効率、実トークン/料金/遅延は**未測定**。機械検査は期待事実・状態・原文照合・保存の契約を検証し、LLM自己評価を合格根拠にしない。

通常のクラウド要約は原則1応答で本文+JSONを返す。短い端末内要約も1guided digestから構成し、全プロファイル再分類の呼出しを削減した。長文は既存の部分抽出/統合を維持し、時系列・変更理由・条件・ID/引用を保つ指示へ修正。全体を処理できない固定形式は黙って切り捨てず失敗を返し、クラウドへ自動送信しない。

## 主な変更ファイル

- 生成: SummaryPrompt.swift、SummaryMarkdownBuilder.swift、SummaryResponseParser.swift、SummaryTemplateChoice.swift、OnDeviceSummarizer.swift、MeetingSummarizer.swift。
- 保存/根拠: SummaryKnowledge.swift、TemplateSummary.swift、SummaryEvidence.swift、Meeting+SummaryContent.swift、SummaryJobFingerprint.swift、MemoraModel+SummaryGeneration.swift、MemoraModel+SummaryKnowledge.swift、ProjectSource.swift。
- 表示: MeetingDetailView.swift、SummaryExtractionView.swift、SummaryFactEditor.swift、SummarySectionIndex.swift、MarkdownTableView.swift、EditableMarkdownDocument.swift、MarkdownDocumentView.swift。
- 統合: MemoraModel+AI.swift、MemoraModel+ProjectContext.swift、Meeting+Privacy.swift、SummaryContentProjection.swift、MeetingShareText.swift、MeetingPDFContent.swift、NotionService.swift。

## 検証結果

| 検証 | 結果・実施範囲 |
| --- | --- |
| iOSビルド/プレビュー | 成功。既存11警告。iOS 27.2 SDK、`bitrig preview -platform iOS`で更新 |
| 全体ホスト回帰 | **8/8成功**。next-generation / design-refresh / background-summary / summary-reliability / adaptive-summary / adaptive-summary-quality / composer-layout / optimization。[結果JSON](host-results.json) |
| 要約の保存・編集・履歴 | 本番メソッド+隔離SQLiteで失敗/再試行/再読込、原文/履歴保持、生成中の競合、本人編集優先、完了済タスクを検証 |
| バックアップ | 実Meeting/TemplateSummaryの6状態・引用・本人編集フラグ・fingerprintを含むpackage往復を追加。既存v1/v2、音声v3、拒否/rollback/reopenも成功 |
| PDF | ホストで13 A4ページの日本語/表と5ページの記録PDFを実生成。検索可能な文字、数値、タスク範囲/状態、取り消し/一時ファイルcleanupを検証 |
| Notion / Gmail / Calendar / MCP | mock transportと実行/承認raceの検証。Notion 188 agent +45 manual、Gmail 135、Calendar 54等。実サービスには接続しない |
| 48スキル / 55市場テンプレート | レジストリ/互換ID/固有定義/プロンプトを検証。Marketplace、GitHub/Linear、MCP選択、人物/プロジェクト/資料、削除/Undo/復元/権限も全体回帰に含む |
| 拡張E2E | 成功、151.86秒（最終再実行）。本文、下部AskAI、capture非表示、音声なしの原文移動、抽出編集/失効、タスク追加/完了、コピー/共有、再生成画面、履歴復元、表セルの完全置換とSQLite原文保持 |
| 保存失敗E2E | 成功、86.98秒。DB保存失敗、再起動後のdurable draft、draft保存も失敗した際のアプリ内保持、再試行と再起動後の確定本文を検証 |
| UI目視 | ライト/ダーク、表の横スクロール、最大Dynamic Type、狭いiPhone画面、キーボード表示、下部AskAIとの余白をスクリーンショットで確認 |

コマンド・ログの所在は[検証manifest](validation.json)。`run-quality-checks.py`には新しい2群も登録し、失敗のログを消さずに後続を実行する。型だけのホストfixtureが古かったGmail/Calendar/Notionの不整合も修復した。本番の承認チェックを緩めて検証を通したものではない。

E2Eは専用と確認したシミュレータへ架空データを投入する。UIKitの2種類の編集メニューと保存失敗で表示されるdraftを実際の操作で検証し、原本DBが変わっていないことも別に要求した。ビルド成功をUI成功の根拠にはしていない。再生成E2Eは画面表示/キャンセルまでで、実モデルの再生成は行わない。

全体8群の後、最終レビューで通常文の重複判定をさらに保守的にした。変更後に要約全群と新旧比較fixtureを再実行し、識別子・金額・否定/当初案の保持を追加検証した。リンクの同一性も抽出/編集とNotionの専用検査で確認し、iOSプレビューも再ビルドして成功した。

## スクリーンショット

- [変更前・ライト](before-light.png) / [変更後・ライト](after-light.png) / [変更後・ダーク](after-dark.png)
- [適応型本文の短文fixture・ライト](reading-light.png)
- [表・左側](table-light.png) / [表・右側へスクロール](table-light-right.png)
- [最大文字サイズ](largest-type-dark.png) / [拡大本文](largest-type-body-dark.png)
- [狭い画面](narrow-light.png) / [狭い画面でキーボード表示](narrow-keyboard.png)
- [抽出編集と失効表示](edited-extraction.png) / [実際の共有シート](native-share.png) / [履歴復元後](restored-history.png)
- [表セルを置換した結果](table-inline-edit.png)
- [編集中セルとキーボードの位置](table-editor-keyboard.png)

すべて架空の画面確認データ。旧画面サンプルそのものを再要約したモデル比較ではない。

## 未検証・残存する制約

ユーザーの指定により実モデルAPI評価は行わない。DeepSeek、実クラウド、Apple端末内モデルの内容品質・実料金・速度は未検証。分割境界の方針訂正を実モデルが最後まで保持するか、提案を決定に誤認しないか、攻撃文に従わないかも実モデルでは確認していない。これらの品質条件を達成済みとはしない。

実機の録音/STT/音声シーク、VoiceOver読み上げ、iOS26実行、実アカウント認証/CloudKit/Notion/Webhook送信、実MCPサービス、Jinba資料生成の既存未検証事項は未検証のまま。ホストのmock transport、偽応答、隔離SQLiteの成功は実サービス成功を意味しない。

次の評価では、同じ35fixtureを承認された実モデルへ送って上記未測定の指標を採点し、期待事実に対する人手レビューを行う。長文の段階圧縮・混合用途・音声認識誤りは優先する。本文と本人編集した抽出の再調整は自動上書きせず、明示的な確認が必要な設計を維持する。

## 実装コミット

`c71ab15` 構成/プロファイル、`1b33d03` 既存Notion fixture修復、`5fea17af` 状態/根拠/保存、`2a63f8df` 読書/抽出UI、`229eaff5` 既存Gmail/Calendar fixture修復、`a6730e2d` 本人編集/検索/共有/復元/キーボード、`8afc4992` 事実とリンクの安全な重複判定。

OpenCode Go / DeepSeekへの限定委譲の実施結果はIMPLEMENTATION.mdに記録。失敗した候補をゲートを飛ばして取り込まず、実モデルの要約品質をワーカーの自己評価で合格にしていない。
