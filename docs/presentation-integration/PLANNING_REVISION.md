# 資料計画と部分修正

## 2026-10-27: 計画の保持

- `PresentationPlan`を資料のoptionalフィールドとして保存。旧資料と旧バックアップはそのまま読める。
- 目的・対象読者・判断事項・未確認の前提、スライドUUIDに結び付いた主張/根拠/未確認事項を保持。
- AskAIの`create_slides.plan_json`から1始まりの番号を安定したスライドIDへ変換する。
  未知の項目・重複・範囲外・過大入力を拒否。資料計画は権限として使わない。
- スライド編集の「目的と構成」で編集。並べ替えで関連を保持し、削除されたページの関連だけ除く。
- SQLite下書きと競合検出を維持。構成のみの変更もcontentRevisionを進め、既存成果物を保持する。
- 65型検査と計画検査、実SQLite保存/再読込/古い画面の保存拒否が成功。

## 2026-10-27: 確認して反映する部分修正

- 資料編集の「AIで一部を修正」から1〜3枚を選択。目的・対象読者・判断事項と選択ページだけを送る。
  他のページは入力に含めず、文章を切り捨てて送信しない。入力上限を超えたら対象を減らすよう案内する。
- 設定済みBYOK（1操作1呼出・最大8,000出力トークン）または既存の端末内AI。
  外部検索・ツール・自動再試行・独立レビューの追加呼出はない。実APIは未実行。
- UUID・ページ数・既知のJSONキー・65型入力・版面を検査。選択外・重複・空・構造欠落を拒否。
- 構造化された表/グラフ/指標のラベルと値と単位/関係/予定、出典(title/locator/excerpt)を保持。
  本文の算用数字・全角数字・漢数字の出現集合も比較するが、文章の意味や数量の文脈の真偽は保証しない。
  数値訂正・表やグラフのデータ修正は原資料を確認して通常のエディタで行う。
- 変更前後のプレビュー、読める本文、機械診断を確認してから明示的に「下書きに反映」。
  さらに既存エディタの保存を押すまでSQLiteの資料は変更しない。元のPPTX/版情報も保持する。
- 生成中は短いshimmerと停止。離脱/バックグラウンドで停止し、修正指示はSQLite下書きへ残す。
- 生成の直前・進行中・結果受領・下書き反映時に権限を再確認。正確な保存済み資料、workspace generation、
  設定/登録モデルrevision、出典fingerprintとprivacy更新日時を束縛する。再開時にgrantを復元しない。
- 会社テンプレート、Memora Intelligence、出典が不完全な旧資料のクラウド再送は拒否。
  とくに既存エージェントの出典は不完全マークの場合があり、その資料はBYOKでもこの操作に渡せない。
  端末内AIまたは手動編集を案内する。従来の原本・共有機能は維持する。
- バックアップは新しい計画も復元。存在しないスライドへの関連、過大計画は受入前に拒否する。

### 検査

- `run-presentation-checks.sh`: 65型ごとの修正応答parse/反映、出力の既存検査。
- `run-artifact-operation-checks.sh --presentation-revision`: 本番の資料/出典権限ガード、workspace A-B-A、
  モデル変更/戻す操作、privacy OFF/ON、更新/削除/保護/復元の拒否。設定とOS境界のみfixture。
- セッション: 送信直前の再確認、重複呼出防止、停止、古い応答が新しい結果を置換しないこと、
  生成後の権限変更、明示的な反映をモックで検査。外部APIの応答品質を検証したものではない。
- 既存6スイートはすべて成功。バックアップの追加検査も成功。CIには部分修正の検査を追加。

### 残る境界

AskAI会話から既存資料を探して直接部分修正する道具、独立LLMレビュー、全体ストーリーの自動改稿、
企業マスター上での部分修正、実モデルの品質/速度/日本語IME/実機の検証は未完了。
計画は`create_slides`のoptional入力であり、以前の呼出にも計画の強制や架空の補完はしない。
計画画面と比較画面はApple標準のForm/List/DisclosureGroupを使い、アプリ全体のUIを置き換えていない。
全65型のOffice/実機最終描画は未完了。全完成条件は引き続き0/65。

## 最終ビルド・Simulatorの確認

- Debug preview成功: `2026-10-27T21-25-01-c5b23d62.log`。
- Release iOS Simulator build成功: `2026-10-27T21-25-03-97965e57.log`。
  両方とも既存の非推奨等11 warnings。iOS 27.1 SDK、iOS 26 target。
- iPhone 18 Pro Maxの架空データで、フォームのラベル、Light/Dark、最大Dynamic Typeの折返し、
  変更前後の表示、1枚の選択、ASCII依頼入力、キーボード表示中のボタン到達、送信前の権限拒否を確認。
  有料APIは呼んでいない。比較画面は固定の架空例で、実AI生成の成功画像ではない。
- 入力欄を埋めた後も意味が分かるよう、目的・対象読者・判断事項・根拠にラベルを保持する。
  `native-app-design`に沿った標準フォームで、最大文字サイズでは縦に再配置される。
- [計画・Dark](planning-labeled-dark.png) / [Light](planning-labeled-light.png) /
  [最大文字サイズ](planning-accessibility-light.png) / [修正前後](revision-comparison-dark.png) /
  [送信拒否](revision-refused-light.png)。[ラベル補強前](planning-before-labels-dark.png)も保持。
- [計画/65型/部分修正検査ログ](planning-revision-checks/presentation-revision.log)、
  [権限検査](planning-revision-checks/presentation-access.log)、
  [バックアップ](planning-revision-checks/presentation-plan-backup.log)、
  [6スイート結果](planning-revision-checks/summary.json)。同フォルダに6本の生ログ。

VoiceOver実操作、Reduce Motion、全端末サイズ、実際の日本語IME変換、実モデルと実機は未検証。
テストはskipせず、確認できた範囲と未確認範囲を分けている。
