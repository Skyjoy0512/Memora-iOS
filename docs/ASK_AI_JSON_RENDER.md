# Ask AI: json-render形式のネイティブ回答

Ask AIのクラウドエージェントが、Markdownの後に`json-render`コードブロックを
生成できる。Vercelの[json-render](https://github.com/vercel-labs/json-render)の
[root / elements / type / props / children形式](https://github.com/vercel-labs/json-render/blob/main/packages/react/src/schema.ts)
を限定カタログで受け取り、既存のSwiftUI部品へ変換する独立実装。
JavaScriptパッケージやWebViewは追加していない。

## 表示と生成

- `NativeAIInterface.instructions`を渡す既存のグローバル・クラウドエージェントが対象。
  オンデバイス、プロジェクト/記録の専用プロンプト、常駐エージェントには追加していない。
- 通常の質問はMarkdown。比較・件数・日程などに図表が役立つときだけ構造化表示を付ける。
  「記録の件数をグラフで」「選択肢を比較表で」のように依頼できる。
- `Stack`は最上位の1〜8部品。`Row`/`Column`は1〜4個の葉を並べる。
  Rowは大きな文字サイズ、またはコンパクト幅で3部品以上になると縦に並べる。
- 葉は既存のTaskList / DocumentCard / ProjectCard / SourceList / ComparisonTable /
  Timeline / Chart / ActionBar / TaskProgress / MailDraftCard / Disclosure /
  CalendarPreviewと、新しいMetric。Metricは数値・指標名と単位・任意の補足を表示し、
  負数も許可する。Chartは従来どおり非負数。
- propsは既存のtitle / columns / items。葉のchildrenは空。
  レイアウト部品のpropsは空。Metricのitemsは1件のみ。

```json
{
  "root": "answer",
  "elements": {
    "answer": {"type": "Stack", "props": {}, "children": ["total"]},
    "total": {
      "type": "Metric",
      "props": {"items": [{"id": "count", "title": "件数（件）", "value": 3}]},
      "children": []
    }
  }
}
```

上は形式説明用の架空値。本番プロンプトでは、与えられた根拠にない数値や記録を作らせない。

## 検証・互換性

`NativeAIComponentStream`は追記されたbyteを走査し、閉じたelementごとに元の
JSON接頭辞とカタログを検証する。完成済みの葉だけを表示し、Row/Columnは子が
揃ってから表示する。elementキーをSwiftUIの安定したIDとして引き継ぐ。
完全なenvelope・閉じたコードフェンス・停止した回答は全体を検証する。

32KiB（JSON内の空白を含む）、最大41element、既存の項目/文字数/数値上限を適用。
未知の部品・props・操作、循環・重複/共有/欠落/未参照element、深いレイアウト、
不正UUID、state / expressions / on / visible / repeat / slotsを拒否する。
上流の全カタログ・状態管理・JSON Patch/SpecStreamプロトコルへの完全互換ではない。

表示JSONは権限を与えない。参照・タスク完了・カレンダー・メールは既存のライブな
権限解決/承認処理を再利用し、ストリーミング中の変更操作は無効のまま。
引用リンクは本文だけに適用し、JSON内の引用符やエスケープを書き換えない。

古い`memora-ui`回答を引き続き読み込む。SQLiteには元の回答文字列を保存するため
移行は不要。コピー・共有・資料保存は既存の`exportMarkdown`経由で新形式も本文へ
展開する。不正/途中終了のUIは隠し、先行するMarkdown回答を残す。

## 確認方法

設定 > 診断とプレビュー > 状態と復旧UIを確認 > 構造化回答（表示の確認）。
明示的に架空データと表示したローカル再生で、モデルや外部APIは呼ばない。
「ストリーミングを確認」で同じ本番パーサー・表示部品を通す。

自動検証: `bash tools/checks/run-intelligent-ui-checks.sh`。
`JSONRenderChecks`は途中表示/安定ID/キャッシュ/エクスポート/旧形式/
不正データ/制限を検証する。会話復元・引用の既存チェックも実行する。

実モデルの生成品質と実際のツール/承認の往復は、設定済みのクラウドモデルと
実データによる別の確認が必要。ローカル表示確認やコンパイル成功をその証明にしない。

## 今回の検証結果

- iOS 27.2 SDK: `bitrig preview -platform iOS`成功。既存の非推奨APIなどの警告11件。
- `run-intelligent-ui-checks.sh`、`run-conversation-evidence-checks.sh`、
  `run-inline-citation-checks.sh`、`run-next-generation-checks.sh`が成功。
  既存の承認付きUIタスク操作、カレンダー参照の失効、保存・復元の検証も含む。
- BitrigのiPhone 18 Pro Maxでローカルの架空回答を表示。指標・比較表・グラフ・日程、
  再生途中の完成部品だけの表示、ダーク表示、accessibility_largeでの文字折返し・
  表の横スクロール・Rowの縦並びを確認。大きな文字の軸ラベルは目盛り数を減らす。
- 実クラウドモデルの生成、実記録からの数値の正確さ、実端末/サービスとの往復は未確認。
