# 企業PowerPoint書式の計測基盤

2026-10-27。開始main: `b81859b95581d77627cf7fcb9176d4b1e20b0013`。
本フェーズは企業書式対応の計測・保存部分。**企業マスター上への新規スライド生成は未実装**。
全65型の最終完成数は引き続き **0 / 65**。標準の登録・個別ホスト検査は65/65。

2026-10-28: 条件限定の[会社PPTX追加export](COMPANY_APPEND.md)を追加した。
本書は計測フェーズ時点の履歴。新規生成の現在の対応範囲・制限・実検査は追補を正とする。

## 実装完了

- `CompanyPresentationAnalyzer`がパッケージの関連付けをたどり、実際に登録されたマスター、レイアウト、使用回数、テーマを計測する。ファイル名の連番や名称の一致だけでは選ばない。
- ページ寸法はEMUの整数で保持。テーマ色・見出し/本文のLatin/日本語フォント、マスターの色対応、文字サイズ例、背景、プレースホルダー、画像/図形の位置を型付きデータで保持する。
- レイアウトに直接指定がない位置は、対応するマスターの枠から継承し、継承元の部品IDも保存する。別の本文枠を推測して使わない。位置未確定、グループの未変換、回転/反転は明示する。
- グラデーションや画像背景を、見つかった最初の色で単色として表示しない。色変換も解決済みのRGBとは扱わない。
- 既存の`Analysis`へoptionalで追加し解析版を3へ更新。旧データは再解析するまでそのまま読める。再解析で原本・ID・版を変更しない。
- 設定の会社テンプレート詳細に、標準フォーム/一覧/開閉項目による計測情報を追加。`native-app-design`に従い、モノトーン・Dynamic Type・意味付き標準コントロールを使い、アプリのナビゲーションやロゴは変更しない。
- 登録・再解析・差し込みの元ファイル読込を50MiB上限の共通経路へ集約。キャンセル、ワークスペース世代変更、復元、書込不可状態では登録/保存を確定しない。
- 計測は端末内のみ。AIへ会社書式の追加送信、有料API、新たな依存関係/固定費は追加していない。

既存の差し込み可否は、引き続き`{{name}}`方式の対応可否であり、計測できたことを新規ページ生成可能の表示に使わない。元ファイル、マスター、画像、テーマ、ノート等の非変更部品を保持する差し込み経路は維持する。

## 検証完了

| 検査 | 結果・境界 |
| --- | --- |
| 型付き計測・継承 | 合成PPTXで関係先、寸法、使用回数、日本語フォント/色、直接指定優先、継承元を検査 |
| XML/パッケージ | Strict/Transitional・任意prefix、欠落/重複/外部参照/階層逸脱、未確定位置、グループ/背景の限界を検査 |
| 原本保護 | 元PPTXと、差し込み対象外のZIP部品のバイト一致を確認 |
| SQLite | production再解析経路で保存・別接続から再読込。保存失敗、編集/削除/世代/復元/保護/キャンセルを検査 |
| バックアップ | optional計測情報と原本ファイルの復元、旧版読込、不正寸法/重複マスターの拒否を実SQLiteで検査 |
| 既存6スイート | next-generation / design-refresh / background-summary / summary-reliability / composer-layout / optimization：すべてPass |
| 標準PowerPoint | 65/65の個別モデル・形状・日本語/PDF文字・編集・再生成・PPTX部品を再検査。Office最終描画ではない |
| Simulator | iPhone 18 Pro Max、Light/Dark、最大Dynamic Type、レイアウト遷移・開閉項目・継承値の実画面を確認 |
| Debug/Release | 最終コードで両方成功。既存11警告。Simulator向けのビルドであり実機検証ではない |

実行コマンド:

```sh
bitrig preview -platform iOS
bitrig build -destination 'generic/platform=iOS Simulator' -configuration Release
bash tools/checks/run-quality-checks.sh --output-dir <SSD上の結果フォルダ>
bash tools/checks/run-artifact-checks.sh
bash tools/checks/run-backup-restore-checks.sh
bash tools/checks/run-presentation-checks.sh
bash tools/checks/run-company-template-profile.sh input.pptx new-output.json
git diff --check
```

ホストの実ログは[checks](company-profile/checks/)、合成データの計測結果は[JSON](company-profile/company-profile.json)。
ビルドのコミット・ログ位置は[builds.json](company-profile/checks/builds.json)。
CLIは既存出力への上書きを拒否し、入力と同じパスを指定しても原本を上書きしない。合成PPTXの拒否前後SHA-256は両方とも`bbfee0414b8164fc909d1179f29cd32d8a0b350dc423474aac2f4b951dc3f8a6`。

ローカル6スイートの後、最終の背景判定修正について資料専用検査を再実行している。
GitHub Actionsの確定結果は、このレポートと同じコミットSHAの[Host quality checks](https://github.com/Skyjoy0512/Memora-iOS/actions/workflows/quality.yml)で照合する。既存の6スイートを無効化/skipしていない。

## 実画面

本番と同じ表示コンポーネントを、productionパーサーで計測した架空PPTXに接続したもの。端末の既存資料を変更せず、会社ファイルの実インポート操作のE2E検証とは区別する。

- [計測概要・Dark](company-profile/screenshots/profile-dark.png)
- [継承位置・Dark](company-profile/screenshots/layout-dark.png)
- [フォント・Light](company-profile/screenshots/layout-light.png)
- [最大文字・上部](company-profile/screenshots/layout-large-top.png)
- [最大文字・注意事項](company-profile/screenshots/layout-large-footer.png)

変更前はXML属性の一覧だけだった。実Beforeスクリーンショットは今回取得しておらず、上記をBefore/Afterの比較証拠とはしない。全画面のUI改修完了やSnapshotTesting/XCUITest実行とも扱わない。表示設定は検証後に元へ戻した。

## 参考OSSの実ファイルと制限

参考HEADは`e5f35e57e14d3998249a559c620a9286c95b4595`。
`measure_deck.py`の関係先/枠/書式計測、`deck_pptx.py`の原本マスター保持方針を参照し、Swiftで実装した。Python/NodeはiOSへ追加しない。既存MIT表示は維持し、他社ブランドは追加しない。

`SuperTemplate_62type.pptx`を本番と同じ解析入口で検査した結果、**既存の安全検査で拒否**された。独立したZIP/XML確認では外部関係はなく、`ppt/embeddings/Microsoft_Excel_Worksheet1.xlsx`〜`4.xlsx`が存在した。埋め込みを拒否する方針を回避/緩和しない。したがって、この参考PPTXの取り込み・マスター適用・最終描画が成功したとは報告しない。[拒否ログ](company-profile/checks/upstream-profile.log)。

合成fixtureの画像ノードは位置計測のテスト用であり、実際のロゴ画像の再現検証ではない。

## 未実装・未検証・次の実装

1. 計測した会社マスター/テーマ/プレースホルダー上に65型を配置し、互換性のあるレイアウトを選ぶexport経路。既存ページへの追加、元ファイル/生成版の関連を保持する操作UI。
2. 表/グラフの詳細書式、画像のロゴ判定、グループ変換、零寸法の線の枠、余白の自動決定、ページ番号/フッターの新規生成。文字サイズは書式例であり全段落レベルの解決値ではない。既存部品を保持することと、新規部品の書式再現を区別する。
3. 企業資料のネイティブ/PDFプレビューとPPTXの一致、PowerPoint/Keynote/LibreOffice/Quick Lookでの会社書式比較。今回はこれらを実行していない。
4. 実会社ファイルの広範な互換性、実機、全iPhoneサイズ、VoiceOver読み上げ、IME。今回の画面はAX情報とSimulatorの画像確認のみ。
5. CPU/RSS/電池/速度の比較は未実測。上限値は保護設定であって実測の省メモリ成果ではない。録音品質/保存形式を変更して高速化したことにはしない。

ビルド時のSectionイニシャライザ指定とテストfixture追加後の旧件数期待値で失敗があり、修正して再実行した。テストを削除/skipせず、解析失敗も成功へ読み替えていない。
