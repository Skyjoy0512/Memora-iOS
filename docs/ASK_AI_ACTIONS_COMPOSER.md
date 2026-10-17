# Ask AI 回答操作と長文入力の仕上げ

2026-10-18。開始時main: `fd7bbc0`。OpenCode担当の構造化UIは統合済みであることを確認した。
`c03e624` の統合、その後のRow/Column (`050c515`)、読み上げ (`a1259cb`)、
表示用fixtureとローカル途中表示、9件のe2e (`fd7bbc0`) を重複実装しない。

## 今回の担当

- `AIResponseActionBar`: コピー・共有・読み上げ・その他の操作。資料保存と再試行はメニューへ。
  再試行は既存 `canRetryAIAnswer` で許される場合だけ提示し、実行時も既存メソッドが再検証する。
  読み上げは既存 `toggleAnswerSpeech` とAudioSessionCoordinatorを維持する。
- `AIAnswerTextSelectionView`: 1つの選択可能な文字列として回答を開く。編集・生成UI・実行操作は持たない。
  本番の出力文字列は既存のNativeAIInterface抽出とAnswerCitations除去を一度行った値を共有する。
  モデルの生成JSONや出典の内部マーカーを選択画面へ別経路から渡さない。
- `AIAnswerActions`: 実データの保存・再試行・読み上げを担当し、表示用callbackへ接続する。
  保存成功後の資料画面、保存失敗、読み上げ失敗の表示は維持する。
- `AIComposerLayoutPolicy` / `AIComposerBar`: 180文字超または4行以上のときに入力欄を広げられる。
  通常は最大6行、拡大は最大12行を基準とし、Dynamic Typeの行高で160/280ptの目安から行数を調整する。
  短文の高さは内容に合わせ、長文は文字を縮めず入力欄内でスクロールする。
  同じTextField・Binding・TextSelection・FocusState・IME監視を維持し、画面や編集用draftを複製しない。
  @非対応のスコープでもローカルの入力監視を使い、送信直前に未確定文字を検証する。
  送信拒否と停止では入力・添付を保持し、受付後にだけ空にする既存経路を維持する。

## OSSの対応とライセンス

参照・部分移植元: `bryanrg22/chatgpt-ios-ui`、固定SHA
`dc6e6a52b14a67051f6534cc674cc32ddd9cb9d1`、
`Sources/ChatGPTUI/ChatGPTView.swift` の回答アクション行、`responseMoreMenu`、
選択用sheet、180文字を超えたcomposerの拡張導線。

回答アクション行と選択用presentationをMemoraのcallbackとSwiftUI構成へ適応した。
入力拡張は操作を参考に独自実装。元の全画面TextEditor/ChatStateは取り込まず、同じネイティブ欄を保持する。
独自の評価送信、架空の「Proモード」、自動Web再実行、分岐のダミー項目は追加しない。
Copyright (c) 2026 Bryan Ramirez-Gonzalez and contributors。MIT全文は既存
`App/Resources/ChatGPTUI-LICENSE.txt` に同梱。依存追加・ブランド素材・サーバー・課金の追加なし。
OpenUI部品の実装ファイルは変更しない。

## 検証の範囲

- `AIComposerLayoutChecks`: 日本語・絵文字の文字数境界、LF/CRLF、開閉時の行数/高さ、巨大入力。
- Debugの既存コンポーザーfixtureへ長文入力ボタンを追加。callbackはローカルの受付/拒否/停止。
- Debugの回答操作fixtureは本番ActionBarを使用し、保存/再試行/読み上げのcallbackはローカル件数のみ。
  実際の資料保存・AI再試行・音声の再生は行わない。
- `tests/answer-actions.e2e.ts`: 既存e2e frameworkの決定的操作のみ。モデル呼び出しなし。
  テキスト選択sheet、再試行不可のメニュー、入力の拡大/縮小/送信拒否による保持を検証する。
- ビルド/回帰/画面結果は完了後に追記する。日本語IMEの実変換、実機VoiceOver、実プロバイダー停止、
  実保存と共有先アプリへの受け渡しは、このfixture成功だけでは検証済みにしない。

## 統合済み・残タスクの確認

- OpenCodeの比較表・根拠一覧・TaskProgressとホスト検証はmainに統合済み。
- Row/Columnの浅い読み取り専用配置、構造化UIのローカル途中表示、SourceList/進捗の
  Light/Dark/大きい文字/Reduce Motionの画像が既にあり、今回繰り返し実装しない。
- 前回までの9件のe2eはリポジトリに登録済み。今回の2件は別ファイルに分け、共通テストを変更しない。
- 別会話が実行中との通知を受けているが、当該会話の内部進捗は直接取得できない。
  この確認時点で共有mainの未コミット差分は今回担当のファイルのみ。別の担当の差分が現れれば
  ステージ・変更せず残す。ブランチの切替や他worktreeの変更は行わない。

次の優先順:

1. P0: 実機VoiceOver/日本語IME/録音と音声の競合、長い会話・大量記録の性能、
   実provider停止と失効を含むE2E。実接続/キー/機材が必要な部分はモック成功と区別する。
2. P1: 実EventKitの許可変更、成果物の保存/編集/共有の通し操作、人物→メール/資料の
   統合シナリオ、複雑な企業Officeの描画と再保存。テンプレートの一般的な完全再現は未達。
3. P1: Composerの添付プレビュー、履歴と入力の操作品質、iOS26非推奨APIの限定移行。
4. P2: 検索の未見日本語コーパス評価・オンデバイス意味検索比較、Deep Researchの主張と根拠の
   意味的一致、追加の読み取り専用UI。Gmail Drafts/送信、正確な請求額上限や未接続backendは別途扱う。

進捗率を新たに推定せず、実装・PoC・モック検証・実接続検証を分けて記録する。

## 検証経過と補正

- 初回e2eはプロジェクト外の出力先を指定して実行前に拒否されたため、専用の内部出力先へ変更した。
- 2件中1件の初回失敗はToggleラベルをタップしてスイッチが変わっていなかったもの。
  失敗時のAX状態と画像で確認し、switchのuncheckと状態assertionに修正した。製品コードの許可条件は変更していない。
- 修正後の2件と既存9件、計11件が成功。reportのmodelTokensは0、agentステップなし。
  結果は `qa/askai2/actions-composer/e2e-regression.json` に要約。
- 画面確認でframe(maxHeight:)が短文でも余白を作ることを発見した。高さ指定を削除し、
  ScaledMetricの行高で表示行数を制限してTextFieldの内容に合う高さを維持する方式へ補正した。
  この後続修正は別の最終ビルド・対象2件の再実行・画像で確認する。
- ホスト: run-next-generation-checks.sh、run-motion-loading-checks.sh、run-optimization-checks.py成功。
  後続の行数補正はrun-answer-presentation-checks.shで再検証し成功。
  同ランナーから新しいrun-composer-layout-checks.shを呼び、共通next-generation実行にも登録した。
- 回答操作: Dark表示、その他メニュー、Lightの選択sheet、実際のネイティブ選択ハンドルとCopyメニュー、
  再試行不可の項目非表示、保存/読み上げcallbackのローカル件数を画像で確認した。

## 最終のUI確認

- 後続修正後のDebugビルド成功。ログ `2026-10-18T08-46-35-830982f9.log`、既存警告11件。
- 後続修正後に対象e2e 2件をキャッシュ無効で再実行し成功。modelTokens=0。
  証拠は `qa/askai2/actions-composer/e2e-final-focused.json`。
- iPhone 18 Pro Max / iOS27.1: 短文は内容に合う高さ、長文の通常/拡大、キーボード中の開閉を画像確認。
  開閉でキーボードを閉じず、画面上のキャレットも保持された。最大文字サイズとReduce Motion有効時も
  送信・拡張の操作がキーボードと重ならないことを確認。確認後は標準文字サイズ/Reduce Motionオフ/元のHomeへ復帰。
- 画像: [短文](qa/askai2/actions-composer/composer-short-light.png)、
  [通常の長文](qa/askai2/actions-composer/composer-long-regular-light.png)、
  [拡大](qa/askai2/actions-composer/composer-long-expanded-light.png)、
  [キーボード併用](qa/askai2/actions-composer/composer-expanded-keyboard-light.png)、
  [最大文字サイズ](qa/askai2/actions-composer/composer-large-text-keyboard-dark.png)、
  [回答操作](qa/askai2/actions-composer/actions-menu-dark.png)、
  [ネイティブ選択](qa/askai2/actions-composer/native-text-selection.png)、
  [再試行不可](qa/askai2/actions-composer/retry-unavailable-light.png)。
- 上記画像はすべて架空データのMemora画面。元OSSデモとのpixel比較や実サービスE2Eの証拠ではない。

- 最終Releaseビルドも成功。ログ `2026-10-18T08-46-36-4f44c7a6.log`、既存警告11件。
  初回Debug/Releaseも成功しているが、最終の行数補正後の上記2ログをビルドの最終証拠とする。
- git diff --check成功。新しいAPI依存・データ移行・有料API実行なし。
