# Memora iOS 総合改善

2026-10-26。開始時点: `main` / `7f928c6`。受信した要件は0-3途中まで。
この文書は今回の方針と到達点。過去の完了報告を現在の検証結果として流用しない。

## 制約

- 個人用の記録・検索・資料生成は端末内を基本とする。記録はSQLite、メディアはファイル。
- 新規固定費、契約、本番デプロイ、クラウド常駐Agentは追加しない。
- ResidentAgent、朝・週次・会議終了トリガー、BGTaskSchedulerを保持する。
  iOSの実行時刻・実行時間はOSが決定し、24時間の実行保証はない。
- 既存BYOK、承認、出典、プライバシー、ワークスペース分離、保存形式を維持する。
- UIの基準は現行DESIGN.md。モノトーン、余白、本文を主役にし、Apple標準の操作を使う。
  ChatGPTの非公開仕様との一致や商標・ロゴの模倣は目標にしない。
- 対象はiPhone / iOS 26以上。iOS 27.1 SDKにないAPIを使わない。

## 現行コードから確認したこと

| 領域 | 実装 | 改善・確認すべき境界 |
| --- | --- | --- |
| UI | DESIGN.mdの共通トークン、フラットな回答、ネイティブ入力、サイドメニュー | 全画面の操作・Dynamic Type・VoiceOverはビルドでは証明できない |
| AI | クラウドSSE、tool calling、書込承認、出典、会話復元 | 実モデルの根拠精度・日本語品質・応答時間・料金は別評価 |
| 資料 | DocumentSlide、PPTXWriter、DocumentPDF、会社書式への差込 | 標準スライドは固定枠、ノート未出力。長文の収まりを共通化する |
| 保存 | LocalStore / MediaFiles、保存失敗時の復旧 | 全量codec/SQLite保存負荷は既存バックログに残る |
| 常駐 | MemoraModel+Residents、ResidentExecutionLimits | OS任せの短時間実行。サーバー常駐へ移さない |
| バックエンド | TeamBackend / UnconfiguredTeamBackend、MemoraIntelligenceの未接続表示 | 未接続を成功に見せない。今回は設計のみ |
| QA | 6つのhost suite、専用Simulatorのe2e、CIのログ保存 | PPTXの文字保持・改ページ・relationship・ノートを独立検査する |

## 実行順と完了条件

| フェーズ | 成果物と完了条件 | 状態 |
| --- | --- | --- |
| 0 | 現状と非対象を固定、既存資料チェック・iOSビルド | 完了 |
| 1 | 標準スライドの共通組版、長文の改ページ、フラットなプレビュー、PDF/PPTXの同じページ構成。文字保持・境界・日本語/絵文字を検査 | 未実装 |
| 2 | PPTX発表者ノート、XML/relationship/編集可能なテキストを独立検査、既存資料・承認の回帰とiOSプレビュー | 未実装 |
| 3 | OSSの採否、固定費を追加しないバックエンド境界、次段の優先順位と未検証項目を記録 | 調査中 |

各フェーズ末に検証結果を記録しコミットする。本番APIを使う品質評価や
実機検証は、ローカルfixture・Simulator・コンパイルの成功と区別する。

## OSSの判断

2026-10-26に公式repositoryとライセンスを再確認。
採用判断では機能数より、iOS互換性、保守負荷、依存、実行費を優先する。

| 候補 | ライセンス・環境 | 判断と理由 |
| --- | --- | --- |
| [PptxGenJS](https://github.com/gitbrent/PptxGenJS) | MIT、JavaScript、Node/browser。packageは4.0.1、JSZip等に依存 | 将来の複雑な表/グラフの比較候補。今回のSwiftアプリにJSランタイムやWebViewを足す利点は小さいため保留 |
| [python-pptx](https://github.com/scanny/python-pptx) | MIT、Python。PowerPointなしで生成/読込 | 開発時の相互運用検査候補。Python実行環境やサーバーをiOS資料生成のために追加しない |
| 既存ZipArchive / PPTXWriter + Apple CoreText | 現行Swift実装とOS標準 | 今回の採用。オフライン、外部API費0、新規依存0。高度な表/グラフ・テンプレート互換性は別課題 |
| 既存MCP / FluidAudio / Lucide | Project.jsonでバージョン固定済み | 今回は更新しない。更新時に依存・ライセンス・advisory・実機負荷を個別確認 |

ライセンスが許諾していても脆弱性がない証拠にはならない。
今回、全依存のCVE監査・更新追従性の保証は行っていない。
新規OSSのコード転載・パッケージ追加は行わない。

## バックエンドの境界（設計のみ）

個人記録、メディア、検索索引、資料組版、iOSのResident実行はローカルに残す。
チーム共有とMemora Intelligenceを実装する時だけ、既存のサービス境界の先へ接続する。
サーバーから端末内storeへ直接アクセスせず、viewから特定クラウドSDKを呼ばない。

| 責務 | 将来候補 | 接続前に必要なもの |
| --- | --- | --- |
| 認証 | Firebase Authentication | iOSのID token取得とサーバーの署名/issuer/audience/期限検証。SMS認証は従量課金として別承認 |
| 認可・API | Cloudflare Workers Freeの適合調査 | 全リクエストでユーザー/チーム所属を検証、入力上限、利用回数制限、timeout、失敗時に閉じる動作 |
| チームmetadata・利用量台帳 | D1 | tenant付きキー、アクセス制御、原子的な利用枠予約/確定/取消、一意request IDで二重課金を防ぐ |
| 音声・写真・成果物 | R2 | 本人の明示的な共有、期限付きURL、サイズ/MIME/hash検査、削除と保持期限。バイナリをD1へ入れない |
| AI API秘密鍵 | Workers側のsecret | アプリにprovider keyを配布しない。上限に達したら停止。利用者BYOK経路と混ぜない |

無料枠は無制限ではない。以下は調査時点の公式掲載であり契約していない。
Workers Freeは日次request/CPU上限、D1 Freeは読込500万行/日・書込10万行/日・
合計5GB、R2 Standard無料枠は10GB-month・Class A 100万/月・Class B 1000万/月。
R2の枠超過やFirebase SMS等は費用を生むため、無料枠の存在だけで有効化しない。
AIモデル利用料はこれらの無料枠に含まれない。Workers Paid / Durable Objects / Agents SDK /
Trigger.dev / VPS / 常時コンテナの構築は次回指示まで保留。

公式資料:
[Workers料金](https://developers.cloudflare.com/workers/platform/pricing/)、
[D1料金](https://developers.cloudflare.com/d1/platform/pricing/)、
[R2料金](https://developers.cloudflare.com/r2/pricing/)、
[Firebase料金](https://firebase.google.com/pricing)。

## 次段の評価

- 実モデル: 同意を得た評価用会議で、出典の正しさ、否定/留保、担当者・期限の非捏造、
  完成率、最初の本文までの時間、総時間、request/credit消費を同時に記録。
- 保存性能: 1,000/10,000件の実codec負荷から部分更新の必要性を判断。
  データ移行はrollbackと実SQLite再読込まで検査してから採用。
- UI: Library / Ask AI / 資料のLight/Dark・大きい文字・キーボード・長文・取消・失敗復旧。
  VoiceOverの実読み上げと実機の熱/電池/バックグラウンドは別の検証。
- Office: PowerPoint/Keynote/Google Slidesで生成物を開き、改ページ・日本語font fallback・
  ノート・編集後の再保存を確認。ZIP/XMLが正しいだけで最終描画を保証しない。

## 今回の検証記録

- 変更前 `run-artifact-checks.sh`: 成功。DOCX/PPTX・差込・実SQLite再読込。
- 変更前 `bitrig preview -platform iOS`: 成功、既存警告11件。
  ログ `2026-10-26T23-09-39-82b5ec31.log`。
- 変更後の結果はフェーズ完了時に追記する。
