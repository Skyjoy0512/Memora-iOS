# Memora統合開発・検証済み到達点

2026-10-27。開始main: `5389cf7e061d8ef76d1e3c3aacd5b3d1c87e0db7`。
このレポートは段階的な実装の到達点であり、指示書全体の完了報告ではない。
**65型の登録・共通描画・個別ホスト検査は65/65。全完成条件の達成は0/65。**

2026-10-27追補: [資料計画と確認付き部分修正](PLANNING_REVISION.md)、[企業書式の計測基盤](COMPANY_PROFILE.md)を追加。
下記は最初の統合時点の検証記録。計画の保持・編集UIからの部分修正は追補を正とする。
AskAI会話からの既存スライド直接修正、独立レビュー、企業書式上の修正は引き続き未完了。
企業書式の計測・保存・表示は実装済みだが、新規ページへのマスター適用は未実装。

2026-10-28追補: [会社PPTXへの構造化ページ追加](COMPANY_APPEND.md)を実装。
上記の「マスター適用は未実装」は前フェーズ時点の記録。現在は条件限定の空白レイアウトで
原本を保持して65型を追加できる。一般会社書式、会社PDF/ネイティブ描画、UI再出力は未完了。

## 実装済み

- b01–b30/m01–m35の対応表、構造化の本文/表/指標/グラフ/図/予定/注記/出典。
  レイアウト別の組版規則と入力制約。図表を同じ箇条書きへフォールバックしない。
- Swiftで動く共通CoreText/CoreGraphics描画から、画面、PDF、編集可能PPTXを生成。
  PPTXは文字・矩形・円・多角形・コネクタ。図表はラスターではない。
  OfficeのネイティブChart/埋め込みExcel/Table編集機能とは異なる。
- create_slides/PowerPointスキルに65型を接続。構成→根拠→関係→型の順序を指示。
  入力/版面を検査してから従来の承認/保存へ渡す。生成上限の旧40枚制限を65枚へ整合。
  標準PPTXの生成はメインactorの外で行い、保存直前にworkspace/取消を再確認する。
- スライド一覧、追加/複製/削除/並べ替え、型/タイトル/本文/表セル/数値/系列値/座標/
  図の接続/期間/注記/ノート/出典の編集。詳細JSONは補助手段として残す。
  SQLite下書き、楽観的競合検出、保存失敗時の入力保持、原本/revision保持。
- 旧資料/backupのoptional decode互換。構造化資料をoutlineに戻して表や図を失う編集を拒否。
- 入力不足、範囲外、文字の縦横overflow、文字枠重複、表寸法、スコア、厳密bridgeの着地、
  placeholder、出典欠落、不自然な強調語、同一出典・項目の数値不整合を診断。
  数値の真偽や論理を自動保証しない。品質の詳細は資料画面とスライド編集から開ける。
- URL共通カードをAskAI/共通project composer、記録メモ、projectメモ、journal作成/編集へ接続。
  入力確定テキストからHTTPSを正規化/重複排除し、クリップボード監視なし。
  既存のDNS pinning/redirect/size/timeout検査を使い、取得・要約は別の明示操作。
  要約先を表示。スキップ/停止/失敗の再試行/本文への挿入を実装。
  元の入力を保ったまま出典URLと要約を通常のテキストとして挿入し、既存の保存/検索へ渡す。
- 設定最下部のOSS一覧。直接/解決済み間接依存、モデル、再利用指針を掲載。
  22個のlicense/noticeファイルを同梱。上流のMIT全文と著作権を保持し、広告/商標を生成へ入れない。
- [低固定費バックエンド設計](../LOW_COST_BACKEND_DESIGN.md)。認証/購入は接続していない。

## 検証済み

| 検査 | 結果 | 境界 |
|---|---|---|
| 65型個別生成 | 65/65 Pass | 架空の短い入力。全実データの完成判定ではない |
| 独立ZIP/XML/関係先/shape ID | 65/65 Pass | XML整合性だけを最終描画の証明にしない |
| 日本語PDFテキスト抽出 | 65/65 Pass | 端末/Officeの全フォント環境は未確認 |
| codec/再生成/編集/empty/異常入力 | Pass | 専用ホストcheck。UI E2E全件ではない |
| 65個の異なるgeometry signature | 65/65 | 型の忠実度や情報設計の良さの保証ではない |
| Quick Look実画像生成/目視 | 65/65生成、全比較シートを目視 | 固定fixture。Office/Keynoteとは別 |
| ArtifactOperationsChecks | Pass | 実ファイル/SQLite保存/再読込/ABORT/共有copy。共有先のOfficeは未検証 |
| inline link/session/security checks | Pass | AI/通信モック。SSRF等の本番fetcher回帰は既存スイートでも実行 |
| URL入力→カード→本文の取得 | Simulatorで成功 | example.comのみ。AI要約は実行していない |
| OSS registry/resource検査 | 22/22 | 同梱内容の到達性。全ライセンス法務審査ではない |
| Debug iOS preview | Pass | 最終ログ16:23:16。既存の非推奨等11 warnings |
| Release iOS Simulator build | Pass | 最終ログ16:25:31。既存の非推奨等11 warnings |
| 既存6スイート | すべてPass | 下記JSON/個別ログ。GitHub Actions本体の実行とは別 |
| Pricing scenarios / runner tests | Pass | 16シナリオ・runner 4件。年額の赤字条件は依然残る |
| XCTest/XCUITest | 未実施 | bitrig test -listは78。Project.jsonにはtest targetがない |
| PowerPoint本体 | 未検証 | 16.114.1の起動は確認。AppleEventが-1712でtimeoutしPDF出力なし |
| 実機/電池/低メモリ耐久 | 未実施 | Simulator/ホストで代用しない |

6スイート: next-generation / design-refresh / background-summary /
summary-reliability / composer-layout / optimization。

CIには既存6スイートを残し、65型/URL/OSSの検査と成果物uploadを追加した。
skipや検査の無効化は行っていない。

## 実レンダリングで見つけて修正した問題

初期のb24ではQuick Lookがcustom geometryの線を期待どおりに描かず、点と線がずれ、
傾きも逆になった。標準コネクタとflipH/flipVへ変更し、実画像とXML回帰で確認した。
元のPoCのnative Chart欠落の根因すべてを特定したわけではない。
今回の標準資料はChartパーツへの依存を避け、同じ問題が起きる経路を使用していない。

インラインカードは空のGroupに付けたtaskが初回入力で動かなかったため、
安定したVStackへ変更。Simulatorで初回カードとExample Domainのタイトル取得を確認した。

## 成果物と比較

- [65型PPTX](catalog-65.pptx)、[65型PDF](catalog-65.pdf)、[元の構造化データ](catalog-65.json)
- [全65型の状態](../PRESENTATION_LAYOUT_MATRIX.md)
- [個別出力検査ログ](presentation-final.log)
- [画像差分の数値](render-comparison/render-comparison.json)と同フォルダのcomparison-0〜10.png。
  左が本番共通描画のPDF、右が実PPTXのQuick Look。厳密pixel一致を合格条件に偽装しない。
- 既存の変更前資料表示は[旧reading screenshot](../comprehensive-improvement/slides-reading-light.png)。
  異なる内容なのでpixel差分のbeforeとは扱わない。

### 実Simulator画像

| 対象 | 画像 | 確認範囲 |
|---|---|---|
| 設定最下部 | [Dark](settings-bottom-dark.png) | 最終行のライセンス導線 |
| OSS一覧/本文 | [一覧](licenses-list-dark.png) / [本文](license-detail-dark.png) | バージョン/全文の実表示（間接依存を追加する前の画面記録） |
| slide編集 | [Light](slide-table-light.png) / [Dark](slide-table-dark.png) | 表のプレビュー、型選択、編集欄 |
| edit/keyboard | [Light](slide-table-edited-light.png) | 架空の表セルへASCII入力。保存済み個人資料は変更していない |
| Dynamic Type | [最大文字サイズ](slide-accessibility-light.png) | フォームへ到達・スクロール。全65型/全操作は未確認 |
| URL | [Light](url-card-light.png) / [Dark](url-card-dark.png) | 宛先表示、skip/取得/要約、取得前後のカード |

日本語IMEはコード/モックの変換保護を検証済み。Simulator自動入力のtypeTextが「検」を
unsupported characterとして拒否したため、変換候補確定までの実操作E2Eは未検証。
VoiceOver実操作/Reduce Motion/全iPhoneサイズ/回転/低メモリ/全画面before-afterは未実施。
既存AskAI/Journal/Library/Project/Onboarding/Auth/Paywallの大幅な再設計は今回行っていない。
既存の短いshimmer、サイドメニュー、上部create、projectのチャット/ファイル/ソース順を維持。

## 性能計測

[生ログ](persistence-1k-10k-50k.log)。Mac上、合成Meeting各20 transcript segments、各21回。
全量JSONエンコードとSQLite atomic batchの検査であり、アプリ実機の保存時間ではない。

| 件数 | JSON | encode中央値 | SQLite中央値 | 合計中央値/p95 | peak RSS |
|---:|---:|---:|---:|---:|---:|
| 1,000 | 6.08MB | 46.7ms | 19.5ms | 66.3 / 122.9ms | 71.0MB |
| 10,000 | 60.8MB | 462.0ms | 115.1ms | 578.7 / 617.7ms | 539.8MB |
| 50,000 | 303.9MB | 2,311.1ms | 849.7ms | 3,168.4 / 3,474.0ms | 2,407.9MB |

この測定に対する保存方式の改善後値はない。高速化したとは報告しない。
新しい65ページPPTXは約1.26MB、最後のホストDebug単発生成33.5ms。
同一条件のbefore比較や分位点がないため、アプリの高速化や端末性能の証明ではない。
CPU/電池/録音/UI FPS/実LLM速度のbefore-afterは未計測。

## PoC・参考のみ

上流HTML/PDFはGolden Referenceとして外部scratchに取得。Node/Python/ChromiumはiOSへ同梱しない。
既存PptxGenJS、office-kit、SnapshotTestingは従来の開発時PoCのままで、ランタイム依存を増やさない。
コードを使っていないOpenDots/OpenMuseは参考設計の区分を維持する。

## 未実装・残る完成条件

1. 65型すべての実データ/境界値/画面編集/AI選択E2E、上流HTMLとの忠実度比較、Office/Keynote/実機の最終確認。
2. レイアウト固有のより厳密なsemantic model、RichText/Image/Icon/Group、統計のunit/軸/成長率/入れ子/根拠グリッドの忠実度向上。
3. 会社マスター/レイアウトの自動選択、任意スライド追加、会社書式PDF、企業書式上での65型の再現。
   現行のCompanyTemplateEngineは安全なマーカー差し込みに限定し、元ファイルを変更していない。
4. 資料の目的/読者/判断/ストーリーラインを保存する計画モデル、既存スライドのAI部分修正、
   予算制限つきの独立内容レビュー、レビュー後の再生成と再検査。
   端末内モデルの小さいtool setには従来どおりcreate_slidesを追加していない。
5. URLのサムネイル、安全なmetadata自動取得の同意設定、生成完了時のIME安全な自動挿入。
   現在は取得を操作後に行い、要約を挿入する操作を残す。全5導線の実保存/RAG E2Eは未実施。
6. 全画面の追加UI磨き込みとbefore-after、iOS snapshot/XCTest/XCUITest target。
7. 約50秒失敗の実ログ/実API確認、標準/高精度の実速度・品質比較、未見RAG評価の追加、
   ResidentAgentの実OS耐久、省電力の実機測定、AAC強制終了復旧の追加改善。
8. 50k件でも全量エンコードを避けるレコード単位保存、移行/backupの大規模回帰、改善後の再測定。
9. 認証/購入/台帳の本接続。年額ライト/Proの最大利用・FX200円の赤字条件を維持して可視化し、
   販売を解禁しない。価格/割引/枠/運営費の再設計は未完了。

追加の固定費、クラウド常駐、サービス契約、外部への個人記録送信、有料AI実行は行っていない。
GitHubへは通常の履歴としてコミットし、最終HEADとpush結果は対話の最終報告に記載する。
