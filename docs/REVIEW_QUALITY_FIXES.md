# 2026-10-11 コードレビュー品質改善

## 調査と順序
基準HEAD: 7a7a96c。常駐AIの通常ツール経由のアクセス、形式だけのWebhook判定、共通の未決見出し、会議寄りの分割メモ、全候補の送信、JSON契約の不一致、原文一致だけの根拠リンクが現行にも存在した。

1. P0: 記録単位の保護、常駐ツール、Webhook・チーム共有、明示クラウド要約の分離。
2. P1: 見出しと分割観点、候補削減とJSON契約。
3. P1/P2: 本人識別評価ハーネス、検証可能な根拠参照、回帰チェック。

## P0
- `RecordPrivacy`: 未判定/一般/個人/機密と独立した外部利用許可。旧記録は未判定・全送信オフ。SQLite/記録バックアップのMeeting JSONに保存し、古いJSONはデコード時に安全な既定を使用。
- `RecordAccessPolicy`を常駐トリガー・読み取り・Webhook・チーム共有で使用。過去の要約形式/用途の保護は再生成で降格しない。職業は送信許可に使わない。
- 常駐専用ツール経路は、許可済み記録だけから検索/本文/タスク/プロジェクト/人物/期間レビューを構成する。未許可ジャーナル・独立タスク・人物メモ・過去AI会話を自動送信しない。権限変更・削除・復元で継続を中断。
- 明示的なクラウド要約のチェックボックスは今回限りの同意。自動アクセス権を付与せず、声の特徴量を入力に含めない。
- 詳細の「その他 → プライバシーと外部送信」で明示設定。一般テンプレートに切り替えても機密保護を解除しない。
- 検証: RecordPrivacyChecksとアプリ内旧JSON互換チェックを追加。実際の外部サービス送信・実機は別途検証。
- 追加防御: 通常のクラウドAsk AIにも同じ記録許可を適用。検索前の文脈・読み取りツール・関連タスクをフィルターし、出典の許可を追跡できない過去会話をクラウドへ再送しない。端末内Ask AI・ローカル履歴閲覧は維持する。外部MCPの既存承認経路は維持する。
- 純粋な機密区分判定でupdatedAtを更新しないよう修正。保存後の比較・権限リビジョンは安定し、自己チェックで往復を確認した。

## 制約
すでに外部へ送信された情報は回収できない。送信開始後の権限取り消しで受信済みデータは消せない。本人の自動確定は精度評価前に有効化しない。

## 用途別要約
- 職業用 `work.*` とカスタム形式には未定義の「未決事項」を追加しない。既存会議形式の補助見出しは維持する。
- 分割メモは形式の見出し・観点を共有し、要望・数量・部材・注意事項を保持するよう要求する。クラウドは候補全体、端末内は確定した形式だけを渡し小さいコンテキストを圧迫しない。
- 自動候補は最大8件。既定形式、詳細概要/議事録/ジャーナル/アクション、内容判定、職業推薦を重複排除する。端末内の分類は表現を拡充したルールによる推薦で、未検証のモデル分類ではない。
- JSON例にtemplateIDを追加。本文のみの指示との矛盾を除き、欠落/候補外IDは未確定のMarkdownとして保存し自動タスクを追加しない。JSONの明示的な空配列をMarkdownから補充しない。
- SummaryPersonalizationChecks / SummaryPromptChecks成功。P1 Bitrig Debugビルド成功（既存警告5件）。実LLMの長文・言い換え品質は未評価。

## 本人識別の評価基盤
- `SpeakerEvaluationSample/Report/Evaluation`: 同意・正解の匿名ID・環境・端末・モデル空間・スコアを扱う。実解析結果と登録特徴量からの収集、JSONエクスポート、指定した複数しきい値の混同行列/FAR/FRRを実装。JSONには音声・embeddingを含めない。
- 不正値・未同意・異なるモデル空間を拒否。人が確認した品質以外は除外。片方の正解クラスが無い率はnull。一般向けの評価用エクスポートUIは追加していない。
- FluidAudio v0.17.7の公開chunk時刻/256次元APIを確認。短い発話・検出された発話重なりのchunkを集約から除外し、集約に使えた発話時間を区間の和集合で記録する。重複chunkを二重に数えない。
- 合成データで収集/暗号化プロフィール互換判定/エクスポート/CLIレポートを検証。実音声のFAR/FRRではない。自動本人確定は引き続き無効。実音声の収集・実機評価は `SPEAKER_EVALUATION.md` の手順で別途行う。
- 声の保存方式・固定モデル・ライセンスは変更していない。追加SDK/API/モデルダウンロードは無し。

## 根拠リンク
- クラウド入力に既存発言UUIDを付け、返却JSONにsectionTitle/sourceSegmentID/逐語引用を要求。中間メモでもIDと引用を保持する。
- 現在の記録にあるID、実際の見出し、8文字以上の原文引用、時刻範囲を検証。存在しない/他記録のID・偽引用は無視する。最大64件に制限。
- 検証済みリンクは記録ID・発言ID・その時点の原文とともに要約履歴へ保存。表示時にも同じ記録/同じ原文/同じ要約であることを再検証。原文編集後の古いリンクは使わない。
- `SummarySection.evidenceLinks` は任意フィールド。新しい検証済みリンクを持つスナップショットはschemaVersion 2。旧版/Markdown/原文一致のリンクは従来フォールバックで表示。音声が無いときは再生ボタンを出さない。
- 根拠IDと引用の一致は要約の意味的正しさを保証しない。複数の要約項目を同じセクションに含めた場合、リンクはセクション単位。項目単位の厳密な対応は今後の課題。

## 競合と互換性
- 要約中の原文/手動要約/プライバシー変更は古い結果より優先。設定変更で要約が停止表示のままにならないよう再生成可能な状態に戻す。
- 文字起こし開始時も復元・保存保護・話者解析との競合を拒否。開始時の原文リビジョンと音声URLを保持し、編集/差し替え/削除後の古い文字起こしを適用しない。
- 既存の話者解析にも音声/原文リビジョン検証があり、手動ラベルと登録済み声のモデル互換性を維持。再登録は既存の保存成功後切り替えを保持。
- 声登録と話者解析をモデルの処理状態で排他し、解析・文字起こし・要約・声登録の実行中はバックアップ復元を拒否する。空になったストアへ同じIDを復元して古い結果が紛れ込む競合を避ける。
- 登録途中に声を削除/無効化した場合、登録リビジョンを失効させる。遅れて完了した登録で削除済み特徴量を再有効化しない。
- Meeting/要約履歴/旧テンプレート/職業設定はSQLiteの既存JSON経路を維持。声特徴量は別の暗号化ファイルとKeychain参照のまま。一般的なバックアップへ特徴量を追加していない。

## API・メモリ・ストレージ
- 分類専用の追加APIは無し。候補書式の計測例は46件/5758文字から7件/1115文字へ約81%削減（日本語文字数であり、プロバイダーのトークン数・実課金額ではない）。実装上の候補上限は8件。
- クラウド本文は60,000文字以下で通常1回。超えると40,000文字単位の中間処理N回+統合1回。従来と同じアルゴリズムだが、根拠UUIDを入力に加えたため境界付近では分割数が増える可能性がある。出力上限時の既存継続呼び出しも別途あり、費用削減を保証しない。
- 必要なID/引用の分だけ入出力は増加する。実プロバイダーのトークン/料金計測・長文品質の比較は未実施。今回有料LLM呼び出しは行っていない。
- 新しいAIモデル無し。評価レポートは明示操作のハーネスのみで自動保存しない。要約履歴の検証済み原文リンクでテキスト保存量が増える（最大64参照/出力）。原音声・embeddingの重複保存は増やしていない。実機メモリ・電池・発熱は未計測。

## 検証記録
- 純Swift成功: PersonalizationChecks（16カテゴリー/116職種/推薦/移行）、SummaryPersonalizationChecks（内容/候補/ID/空配列）、SummaryPromptChecks（見出し/順序/分割観点/契約）、SummaryLayoutChecks（表示順）、RecordPrivacyChecks、SummaryEvidenceChecks（従来テストも維持）、SpeakerProcessingChecks、SpeakerEvaluationChecks。
- 既存回帰成功: RecordingMarkerChecks、AIJournalPrivacyChecks、AIHistorySearchChecks、AgentResearchAssignmentChecks。
- 評価CLIの合成4試行: しきい値0.7でFAR/FRR=0.5/0.5、0.85で0/0.5という期待値を確認。精度評価用のしきい値を採用したわけではない。
- 2026-10-11のBitrig Debug最終ビルド成功、既存警告5件。途中の追加SelfChecks初期化エラーを修正し、機密判定の時刻更新による往復チェック失敗も修正。
- シミュレーターで「Personalized summary compatibility」「Review privacy and evidence」「Occupation-linked summary defaults」「Speaker profile storage」「Store migration」「Journal timeline」「Task and journal compatibility」等の成功表示を確認。旧実記録が開き、未判定の全外部送信スイッチがオフ/無効であることも確認。実記録の許可変更・データ初期化は行っていない。
- 2026-10-12の追補Bitrig Debugビルドも成功（既存警告5件）。今回の実機検証は無し。音声登録/モデル解析の実機精度、モデルダウンロード中断・長時間競合の実機ストレス、実LLM・Webhook・チームへのネットワーク経路は未検証。

## 残存リスク・次の課題
1. 同意のある実音声で環境/機種/話者を分けた評価と、検出できない雑音/重なりの評価。本人確定のポリシーはその後。
2. 接客/介護/作業/会議/休日の長文を実LLMで比較。端末内はルール推薦であり、Foundation Modelsによる用途分類は未導入。
3. 外部サービスの送信ペイロードと権限取り消しのE2Eテスト。開始済みリクエストの回収はできない。
4. クラウド会話履歴の出典と許可を保存し、安全に続きの文脈を再利用する。現在は保護を優先して過去会話を再送しないため、クラウドで「さっきの件」のような依頼は情報を再指定する必要がある。
5. 手動で入力した質問/添付/明示メモリ/承認した外部連携には記録の機密区分を自動適用できない。本人が送る情報・所属先の方針を確認すること。機密区分の自動検出や法的適合性は保証しない。
6. ジャーナル単独メモ・独立タスクには記録単位の外部許可UIがまだ無いため、クラウドの読み取り対象から除外している。端末内の閲覧・編集・履歴は維持するが、それらをクラウドAsk AIへ渡す許可設計は次の課題。

## ファイル一覧（7a7a96cからのレビュー修正全体）

追加:
```text
App/GeneratedSummaryEvidence.swift
App/Meeting+Privacy.swift
App/MemoraModel+AutomaticRecordTools.swift
App/MemoraModel+RecordPrivacy.swift
App/RecordAccessPolicy.swift
App/RecordPrivacy.swift
App/RecordPrivacySettingsView.swift
App/SpeakerEmbeddingQuality.swift
App/SpeakerEvaluation.swift
App/SpeakerEvaluationReport.swift
App/SpeakerEvaluationSample.swift
App/SummaryEvidenceLink.swift
docs/REVIEW_QUALITY_FIXES.md
docs/SPEAKER_EVALUATION.md
tools/checks/RecordPrivacyChecks.swift
tools/checks/SpeakerEvaluationChecks.swift
tools/checks/SummaryPromptChecks.swift
tools/speaker-evaluation.swift
```

変更:
```text
App/BackupPackage.swift
App/FluidSpeakerDiarizationService.swift
App/Meeting.swift
App/MeetingDetailView.swift
App/MeetingSummarizer.swift
App/MeetingSummary.swift
App/MeetingSummaryInput.swift
App/MemoraModel+AI.swift
App/MemoraModel+Agent.swift
App/MemoraModel+AgentTools.swift
App/MemoraModel+Backup.swift
App/MemoraModel+Memory.swift
App/MemoraModel+Personalization.swift
App/MemoraModel+Processing.swift
App/MemoraModel+Speakers.swift
App/MemoraModel+VoiceProfile.swift
App/MemoraModel+Residents.swift
App/MemoraModel+Webhooks.swift
App/MemoraModel.swift
App/OnDeviceSummarizer.swift
App/SelfChecks.swift
App/SpeakerAnalysisResult.swift
App/SpeakerIdentificationService.swift
App/SummaryEvidence.swift
App/SummaryGenerationSheet.swift
App/SummaryMarketTemplate.swift
App/SummaryPrompt.swift
App/SummaryResponseParser.swift
App/SummarySection.swift
App/SummarySectionIndex.swift
App/SummaryTemplateSelector.swift
App/TeamShareError.swift
App/TemplateSummary.swift
App/VoiceProfileView.swift
docs/VOICE_ENROLLMENT.md
tools/checks/SummaryEvidenceChecks.swift
tools/checks/SummaryPersonalizationChecks.swift
```
