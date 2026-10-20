# ChatGPTに近い会話中心のUI — 2026-10-20

前段の画面横断整理に続き、Ask AIとサイドメニューの操作部を磨き込んだ。
ネイティブUI設計とLiquid Glassのスキルに沿い、本文と操作の階層を分離する。

## 方針と参照

[OpenAI公式UI guidelines](https://developers.openai.com/plugins/concepts/ui-guidelines)を再確認。
システムフォント、少数の文字階層、中立色、アウトラインアイコン、一定の余白という
原則をSwiftUIへ適用した。ReactやWebViewは導入していない。
これは公開された設計原則の移植であり、ChatGPT iOSアプリの非公開寸法の再現ではない。
24pt角丸・680pt最大幅・20pt操作アイコンなどはMemoraの既存トークンを使う。

Appleの[文字入力](https://developer.apple.com/design/human-interface-guidelines/text-fields)、
[サイドバー](https://developer.apple.com/design/human-interface-guidelines/sidebars)、
[Typography](https://developer.apple.com/design/human-interface-guidelines/typography)も参照。

## 今回の変更

- **ヘッダー**：丸いGlass装飾を外し、メニューアイコンの隣にMemoraと開示記号を配置。履歴・検索・新しいチャットは同じ処理を呼ぶ。
- **入力欄**：Ask AIタブでは、入力と操作の2段構成・横幅をフォーカスにかかわらず維持。通常の画面ではコンパクトな入力欄を残す。空の音声入力はアウトライン、送信・停止・音声入力中は反転色の円にする。
- **下書きと移動**：表示上の拡大と実際の入力操作を分離。下書きが残っていてもキーボードを閉じると下部タブへ戻れる。日本語IME・カーソル・単一のネイティブTextField・SQLiteドラフトは維持。
- **メッセージ**：ユーザーの複数行メッセージにDynamic Typeで拡大する行間を追加。回答は引き続きバブルのないMarkdown本文。
- **回答の操作**：アイコンを共通20ptへ。出典の装飾的な点を資料アイコンと実際の発言件数に置き換え、操作枠を44ptへ拡大。大きい文字では回答操作と出典を縦に並べる。
- **サイドメニュー**：ワークスペースを先頭にし、内側のカードを撤廃。アカウント・プラン・設定を下部へ集約。既存のプロジェクト・資料・人物・外部レコーダーは同じ入口を維持する。

`SidebarAccountFooter` と `AIReplyActionsRow` は独立したView。
親の表示整理だけでなく、操作とスクロール／文字サイズへの適応の責務を分けた。
新旧のフッターや操作行を二重管理しない。

最大文字サイズではプラン名を「プラン」、ゲストの補助文を「サインイン」にする。
読み上げ名のMemora Plusと上部の保存先説明は残し、同じ説明で縦幅を二重に使わない。
設定の44pt円形枠はButtonのラベル内へ置き、見えている枠全体を押せるようにする。

## 保持するもの

タブのUISegmentedControl、＋のGlass／popover／zoom、スクロール追従、
録音・取込・要約・保存処理、API、課金確認、権限、BYOK、ツール実行、出典解決は変更しない。
コンポーザー自身のネイティブGlassと処理中の表示は維持する。
空チャットに挨拶・ロゴ・ダミーの質問候補を追加しない。
サイドメニューからのサインイン・プランの入口は維持するが、未接続サービスを接続済みとは表示しない。

## 比較画像

変更前は `34608b8` の実アプリ、変更後は今回のビルドを同じ専用iOS端末で撮影する。
ユーザーのプレビューのデータは初期化しない。画像の生成・合成は行わない。

| 状態 | Before | After |
|---|---|---|
| 空チャット Light | [画像](chat-surface/before/empty-light.png) | [画像](chat-surface/after/empty-light.png) |
| 空チャット Dark | [画像](chat-surface/before/empty-dark.png) | [画像](chat-surface/after/empty-dark.png) |
| 入力中 Light | [画像](chat-surface/before/draft-light.png) | [画像](chat-surface/after/draft-light.png) |
| 入力中 Dark | [画像](chat-surface/before/draft-dark.png) | [画像](chat-surface/after/draft-dark.png) |
| メニュー Light | [画像](chat-surface/before/sidebar-light.png) | [画像](chat-surface/after/sidebar-light.png) |
| メニュー Dark | [画像](chat-surface/before/sidebar-dark.png) | [画像](chat-surface/after/sidebar-dark.png) |

追加のAfter：
[下書きを残してキーボードを閉じた状態](chat-surface/after/draft-navigation.png)／
[@候補](chat-surface/after/mentions-light.png)／
[文章の表示部品 Light](chat-surface/after/conversation-fixture-light.png)／
[Dark](chat-surface/after/conversation-fixture-dark.png)。
最後の2枚は既存の表示比較画面にある架空の文章であり、実サービスの回答例ではない。

## 検証

`bitrig preview -platform iOS` は成功し、プレビューへ反映。
最終ログ：`2026-10-20T18-27-38-9b38deb2.log`。iOS 26ターゲット／27.1 SDK。
MapKit・OAuth・App Intentsの既存警告11件が残る。

以下のホスト検査は通過。新規の表示契約5件は構造検査であり、実機の見た目の証明ではない。

- `bash tools/checks/run-design-refresh-checks.sh`
- `bash tools/checks/run-ask-ai-plugin-checks.sh`
- `python3 tools/checks/run-optimization-checks.py`

`bitrig test` は、このProject.jsonにXcodeテストターゲットがないため終了コード78。
XCTest成功とは扱わない。

初回実装の標準サイズ11/11件が通過。新規3件に加え、回答操作、長文入力、
グローバル／プロジェクトの@選択、会話の文字組み、設定のトピックと移設先を確認した。

その後のフッター調整を含む最終ビルドでも、新規3件＋設定3件の6/6件が通過。
Light／Dark、下書きのタブ往復とSQLiteからの再読込、履歴／検索、プロフィール編集、
設定の永続化、AI・録音・連携・プランの入口を対象とした。
設定ボタンは44pt以上の実寸を確認し、20ptのアイコンから外れた枠内の点を押して
実際に設定が開くところまで検査した。

初回の最大文字サイズ4件も通過したが、画像レビューではプラン名が窮屈に折り返していた。
テストの通過だけで完了とせず、補助文の短縮とラベル内の操作枠を修正して再検証した。

最終ビルドのAccessibility XXXLも4/4件が通過。
Light／Darkの入力とサイドメニュー、下書きを保持した移動、@候補の位置と操作枠、
検索語の消去とキーボード維持を確認した。専用端末は検査後にLarge／Lightへ戻す。

なお、途中の一実行ではXCTest経由の一括消去`fill('')`が数文字を残し、
実行器の読み戻し検査で停止した。原因をアプリと実行器のどちらとも断定せず、
入力の完全一致を確認してから実際のソフトキーボードの削除キーを使う検査に変更した。
送信ボタンが消え、音声入力へ戻り、次の空画面でプレースホルダーが表示されることを確認する。
この調査でアプリの入力・IME処理は変更していない。
同じ削除キー操作を含むLight／Darkの撮影ケースも、通常のLargeへ戻して1/1件が通過した。

大きな文字のAfter：
[空画面 Light](chat-surface/after/empty-accessibility-light.png)／[Dark](chat-surface/after/empty-accessibility-dark.png)／
[入力 Light](chat-surface/after/draft-accessibility-light.png)／[Dark](chat-surface/after/draft-accessibility-dark.png)／
[メニュー Light](chat-surface/after/sidebar-accessibility-light.png)／[Dark](chat-surface/after/sidebar-accessibility-dark.png)／
[@候補](chat-surface/after/mentions-accessibility.png)／[検索](chat-surface/after/search-accessibility.png)。

ケース名・実行ID・各段階の結果は [RESULTS.json](chat-surface/RESULTS.json) を参照。
全45件の一括実行ではなく、変更範囲に対応した選択実行として記録する。

## 確認の境界

実機VoiceOverでの聴取、手動の日本語IME変換、iOS 26での実行、実マイク、
認証済みプロバイダー／課金／外部連携は今回の表示検査からは証明できない。
出典件数・折り返し・コールバックの接続はソース検査で確認するが、
実サービスの根拠発言を開く全条件のE2Eを新たに網羅したわけではない。
