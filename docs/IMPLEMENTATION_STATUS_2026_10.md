# 総合改善・今回の到達点と残作業

2026-10-27。アプリ改修HEAD: `1a659bf`（後続の開発PoC/文書commitを除く）。
**全文のPhase 1〜5はまだ完了していない。** 監査に加え、費用や本番設定が不要な
資料のデータ保護・初回体験・ログイン/プランUI・開発用OSS検証を実装した。

## 成果物 A〜I

| 成果物 | 場所・到達点 |
| --- | --- |
| A 総合監査 | [AUDIT_2026_10.md](AUDIT_2026_10.md)。最新main再取得、P0/P1/P2、実装/未接続/未検証を区別 |
| B OSS比較 | [OSS_EVALUATION_2026_10.md](OSS_EVALUATION_2026_10.md)、[35候補の固定SHA/ソース証拠](comprehensive-improvement/oss-evidence.json)。不存在の候補もエラーを保持 |
| C UI/UX | [UI_UX_2026_10.md](UI_UX_2026_10.md)。Onboarding/Auth/PlanのBefore/After、最大文字/Dark、非破壊サンプル導線 |
| D PowerPoint | [PRESENTATION_QUALITY_2026_10.md](PRESENTATION_QUALITY_2026_10.md)。共通pagination/notes、企業artifact保護、PptxGenJS/office-kit実行、Quick Lookの欠落と画像差分 |
| E 認証/課金/backend | [BACKEND_DECISIONS_2026_10.md](BACKEND_DECISIONS_2026_10.md)、[PRICING.md](PRICING.md)。固定費なしの候補と契約境界、年額赤字条件を再計算 |
| F 性能 | [監査の実測表](AUDIT_2026_10.md#性能の基準値)。1k/5k/10k/50kのproduction codec/SQLite、21試行。**baselineであり高速化Before/Afterではない** |
| G CI/QA | [QUALITY_TESTING.md](QUALITY_TESTING.md)、[6 suite実結果](comprehensive-improvement/host-suites-20261027.json)。Debug/Release、Simulator、Mac画像比較PoCとnative iOS test host制限を分離 |
| H 未対応 | 下表。実機/有料API/本番接続/Office最終描画の未確認を完了扱いしない |
| I コミット | `7c7e60a` / `a17e260` / `8d33ca4` / `2b1ce4f`、全文受領後 `a74ae4f` / `e8565f7` / `2bc6986` / `1a659bf`。後続PoC/文書はgit logで追跡 |

## 検証の記録

- 環境: Mac arm64、macOS27.0.1、Swift6.4、iOS27.1 SDK、iOS26 deployment。
- Debug: `bitrig preview -platform iOS`成功。最終アプリ改修のlog `2026-10-27T06-31-08-3a2769b4.log`、既存11warning。
- Release: `bitrig build -destination 'generic/platform=iOS Simulator' -configuration Release`成功。
  最終改修後のlog `2026-10-27T06-38-34-f1a771e1.log`、既存11warning。配布archive/署名/実機ではない。
- 6 host suite: next-generation/design-refresh/background-summary/summary-reliability/composer-layout/optimizationが全pass。
  最後の録音入口の整理後もdesign-refreshを再実行してpass。skipは追加していない。
- Mac SnapshotTesting1.19.7: 2 XCTest/0 failure、実画像5一致/5差分。`diffV2`を使い、baselineを自動記録・更新しない。
- `bitrig test -list -json`: exit78。標準Project.jsonにiOS XCTest targetがなく、iOS XCUITest/native snapshot captureは未実行。
- Microsoft PowerPoint/Keynote exportは両方AppleEvent timeout(-1712)。Quick Lookで表紙の日本語は描画できたが、chart欠落を確認。
  したがって、高忠実度/全chart正常/Office互換性に合格したとはしない。
- GitHub Actionsは[既存workflow](../.github/workflows/quality.yml)を維持。push後のrunのHEADと結果をGitHubで照合し、
  以前のGreenを新commitの合格に流用しない。CIの実行履歴はGitHubのActionsで確認できる。

## 未対応と次の実装順

| 優先 | 領域 | 次の安全な完了条件 |
| --- | --- | --- |
| P0 | AAC強制終了/容量不足 | 実機kill/再生可否の再現。segment化を非破壊の独立PoCで比較。動作中fileを書換えず、復旧不能を成功扱いしない |
| P1 | typed slides / native PPTX | title/bullets/notes/UUID/backupを維持したversioned model。2column/comparison table/processを共通preview/PDF/editable PPTXで実装し、未知layout/elementを黙って失わない |
| P1 | slide編集 | native List/Formで追加/削除/複製/並替/notes/sources。既存expectedUpdatedAt検査を使い、AI再生成のwrite承認を維持 |
| P1 | 企業PPTX | size/master/layout/theme/font/logo/placeholderを構造化分析。元fileは不変、対応範囲を表示。新exportの生成・検査・原子的保存後にのみ旧export更新 |
| P1 | Office視覚検証 | PowerPoint/Keynote/LibreOfficeの利用可能なrendererで全slide描画・編集/再保存。日本語/表/chart/notes/画像/overflow/PDF比較を実施。現在の自動export timeoutを解消する必要あり |
| P1 | SQLite部分更新 | 全Meetingを書込む経路とbackup/restore/rollbackを棚卸し。既存schemaと互換の段階移行を別fixtureで測定し、変更前後p50/p95/max/RSSを同条件比較 |
| P1 | iOS native test host | Bitrig標準projectの制約を解決したhostでSnapshotTesting/XCTest/XCUITest。全画面・keyboard/IME・empty/error/loading/selectionを自動撮影/差分検査 |
| P1 | 要約50秒/実API | 許可されたfixtureと利用費予算でTTFT/完了率/意味/出典/実usageをA/B。mock時計の成功を実DeepSeek成功としない |
| P1 | 認証/課金 | Firebase/Apple/Google/StoreKit設定が必要。UI未接続を維持し、内部signIn placeholder等を本番adapterへ置換。local planを課金台帳にしない |
| P2 | Ask AI/sidebar/journal/library/project | 既存IA/recording/STT/@/approvalを維持し、全stateのBefore/After・小型端末/VoiceOver/IMEを検証。今回の3画面改善で全面完了としない |
| P2 | RAG/MCP/Resident | 日本語gold dataset、real transport/OAuth失効、予算/権限/中断/重複、実機電池/熱/通知を確認。未検証の外部読取をautomatic jobへ追加しない |

## 実施しないこと

クラウド常駐Agent、Workers Paid/DO、Trigger.dev、有料job/VPS/container、新規月額固定費、
本番Firebase/Supabase/StoreKit設定、外部アカウント登録、本番deploy、有料AI APIの実行は行っていない。
既存Resident/BGTaskScheduler/朝・会議後triggerは保持。ロゴ/Liquid Glass/journalの方針、
個人SQLite・backup・録音・privacy/approvalの境界を維持する。
