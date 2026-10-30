# Lucideアイコン全体レビュー — 2026-10-30

## 変更範囲

アプリが描く操作・ナビゲーション・状態アイコンをLucideへ統一した。
`App`、`Shared`、ウィジェット、共有拡張のSwiftコードを走査し、共通描画と呼出側を見直した。
設定やプロジェクトが保存した236種類のIDは全て維持し、本文編集用の見出しと番号付きリストを追加した（計238種類）。
全対応表は[LUCIDE_ICONS.md](../LUCIDE_ICONS.md)、提供元は[Lucide](https://github.com/lucide-icons/lucide)。
既存のLucideSwift 0.9.11を使用し、プロジェクト設定や依存バージョンは変更していない。

| 見つかった問題 | 修正 |
| --- | --- |
| 8種類のIDがLucide未対応でSFへ戻っていた | 省略のないswitchへ変更し、全IDをLucideで解決 |
| UIKit経由の描画と本文編集が別の画像経路だった | SwiftUI／UIKit／ウィジェットが同じテンプレート描画を共有 |
| 画像へ`.font`を指定してもサイズが変わらない | 図形を描画する実際のpoint sizeへ移動。本文の文字サイズは維持 |
| コネクタだけ旧サービス画像だった | mail／notebook／calendar／hardDrive／code／plugへ統一 |
| 箇条書きと番号付きリストが同じ図形だった | list／listOrderedに分け、見出しにはheadingを使用 |
| 再生の旧SFアイコンに「15秒」の意味があった | Lucide回転図形に実際の秒数を重ね、読み上げ名も維持 |
| ラスタ画像へSF専用アニメーションを指定していた | opacity遷移へ変更。録音状態のラベルとReduce Motionは維持 |
| 装飾画像が「Lucide Icon」と読み上げられた | 画像自身は空ラベルにし、操作名は既存のButton／Labelが供給 |

Memoraのブランドマーク、AI提供元のロゴ、利用者の写真、ジャーナル背景写真は識別・コンテンツ画像として保持する。
OSが描くNavigationLinkの矢印やシステムシートの内部表示はOSが管理する。
旧コネクタ画像の出典は[CONNECTOR_LOGOS.md](../CONNECTOR_LOGOS.md)に保存し、現行表示には使わない旨を追記した。

## 検証中に修正した既存不具合

- 「計測と自己チェック」へ進むと設定トップへ戻り、その後カテゴリを開けなくなる現象を実画面で確認した。
  `PerformanceLogView`の内側の`NavigationStack`を除き、設定側のスタックへ統一した。
  修正後は一覧へ進めることを確認し、重複する閉じる操作も除いた。
- 一覧の失敗から、要約の`- **予定アクション**:`がセクション見出しとして認識されず、
  直前の決定事項へ混ざる問題を確認した。見出しを認識するよう修正し、
  ハイフン／アスタリスク、半角／全角コロン／省略、アクション表の有無を回帰検査へ追加した。
- 添付読み込みの自己チェックが旧上限8,000文字のままだった。実装の60,000文字という上限を参照する形にした。
  実際の読み込み上限は変更していない。

## 検証

- `bitrig preview -platform iOS`：アプリとウィジェットのビルド成功、プレビュー更新。
  最終ログ`2026-10-30T12-50-26-1d459167.log`。SDK iOS 27.1／最低iOS 26。MapKit・OAuth・App Intentsの既存警告11件は残る。
- `bash tools/checks/run-design-refresh-checks.sh`：通過。アイコンの全対応、旧ID、SF直接描画の混入、サイズ指定を検査する4件を追加。
- `bash tools/checks/run-memory-artifact-checks.sh`：通過。資料生成・65種類の法人テンプレート・バックアップ等の既存検査も通過。
  `run-artifact-checks.sh`の解析用コンパイルにも`SlidePage`／`SlidePageLayout`が必要だったため依存リストを補修した。
- `PluginIconChecks`：旧画像経路の削除後に再コンパイルして通過。サービス別の図形、旧ID、不明ID、スキルの往復保存を確認。
- 変更前後のenum比較：旧236種類のraw valueが全て同一であることを確認。
- シミュレータ（iPhone 18 Pro Max）：ライブラリ、サイドメニュー、設定、連携一覧の実画面を確認。
  連携一覧では6サービスのLucide図形と実際の状態ラベルを確認。設定のLight／Darkでテンプレート色と図形の視認性、AX上の操作名と汎用画像ラベルの解消を確認。
- 診断画面の`Icon assets`／`Destination icons`／`Legacy artwork icon aliases`：成功を確認。全238種類×12／20／48ptの実ピクセル検査を含む。
- 設定表示の静的検査6件：通過。診断画面へ独立したNavigationStackを再導入しない検査を追加。
- 要約のprompt／poster／pipeline／layout／template-notes／relation検査：通過。図解検査の古いモック署名を現行APIへ合わせ、`run-infographic-checks.sh`も通過。
- 最終ビルド起動後の`SelfCheck failed`ログ：0件。修正前に確認した要約抽出・添付上限の2件も解消。
- `git diff --check`：通過。

全画面を1つずつ操作した検証や、実機上での全ウィジェット表示、Office側のレイアウト検証を完了したとは扱わない。
資料生成のホスト検査はZIP／XML／保存互換性の検証であり、Office／Keynoteの最終描画を保証しない。
