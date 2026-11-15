# 共通AI処理改善（2026-11-16）

基準HEAD: a16d3edd（依頼のe61f674eより新しい）。開始時mainはclean。

## 契約

既存Source Adapter/抽出 → MeetingSummaryInput/TranscriptSegment/SummarySourceIndex →
SummaryTokenBudget/SummaryInputPartition → MeetingSummarizer → SummaryKnowledge →
既存の本文・Ask AI・検索・人物/プロジェクトを使う。新しい要約エンジンやDBは追加しない。
入力形式固有の取得・OCR・STTは既存adapter側に残す。Knowledgeは原文の代替ではない。
録音中のクラウド分析・ライブSTTからの先行要約は今回の対象外。
保存済みSourceMediaChunkRevisionとライブ文字起こしは維持する。

## 単位1: 部分応答の受理ゲート

応答の完了はCloudSummaryResponse/stream終端検査、構造と根拠の受理は
SummaryPartArtifact.acceptance、キャッシュ保存はscope/authorize/leaseで別に判定する。
JSONの必須項目欠落、切断、誤型、空根拠、存在しないID、別partの引用、架空引用は
最終統合へ渡さずgenerationFailedとする。authorizeやcache scopeが無い場合も同じ。
分離できない自由記述notesの一部だけを残す修復は行わず、追加APIも呼ばない。
旧自由記述は従来どおり利用可能だがキャッシュ保存しない。

引用一致は文の意味的整合性や網羅性の証明ではない。話者・数値・否定・訂正・提案/決定の
意味的誤りは独立した評価を必要とする。根拠IDが有効なだけで意味検証済みと呼ばない。
保存・編集・完了タスクの既存確定処理は変更しない。

検証: run-summary-reading-checks.sh成功（実orchestration、mock API、既存parser）。
追加10ケースは不正partからmerge/修復requestが送信されないことを検証。
iOS bitrig preview成功、既存11警告。途中にAcceptance内Selfの型指定誤りでcompile失敗、
明示型へ修正後に両検証を再実行し成功。実モデル/実機の検証はしていない。
ログ: /tmp/memora-common-p0.log（失敗）、/tmp/memora-common-p0-r2.log（成功）。
Preview: 2026-11-15T15-48-47-94f9efce.log（Bitrig logs）。
