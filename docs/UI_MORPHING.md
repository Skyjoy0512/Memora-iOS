# Apple純正の画面遷移モーフィング（2026-11-08）

既存のナビゲーション、シート、入力欄、配色、レイアウトを変えずに、
**画面遷移（push）だけ**を`matchedTransitionSource`と`navigationTransition(.zoom)`で
Apple純正の拡大遷移にした。ボトムシート（作成メニュー、ライフログ作成）は
iOS標準の下から上へのシート表示を維持する。独自のscale/opacity/GeometryReaderによる
疑似Liquid Glassは追加していない。

## 採用したAPI

- `matchedTransitionSource(id:in:)` + `navigationTransition(.zoom(sourceID:in:))`
  - 公式ドキュメント: `navigationTransition`は`NavigationStack`内、またはシートで
    表示されるビューに適用する。コンテナの内側ではなく、シートのルートに付ける。
  - iOS 18以降のAPI。Deployment Targetは26.0のため、27専用分岐は不要。
  - Reduce Motionがオンのときは`navigationTransition`を付けず、標準の遷移にする。
- 既存の`glassEffect` / `MemoraGlass`を維持。Glassの二重適用はしない。
- `Menu`はシステム所有の表示を維持（AskAIの＋、ワークスペースのメニュー）。
  `popover`への置き換えは、キーボード表示時の操作性と既存メニュー動作を
  壊すため行っていない。

## 画面別

- ホーム: 右下の既存作成ボタンから`CaptureMenuSheet`を標準のボトムシートとして
  下から上へ表示する。ボタン位置・シート内容・アクション順は不変。
- ジャーナル: タイムラインの各行の＋と末尾＋、空の日の追加ボタンから、
  既存の`LifeLogCreationSheet`を標準のボトムシートとして下から上へ表示する。
  挿入時刻の計算（`JournalInsertionTime`）は変更していない。
- ライブラリ: 保存済み参考資料、録音、共有記録のカードから詳細へzoom遷移。
- ワークスペース/プロジェクト: `ProjectWorkspaceRow`の資料・録音・文書カードから
  詳細へzoom遷移。ソース追加と参照の処理は変更なし。
- 参考資料詳細: 添付資料の行から別の資料詳細へzoom遷移。
- AskAI: 右下FABは追加していない。中央の入力コンポーネントと既存の
  `Menu`（＋、@、ツール）を維持。

## iOS 26 / 27

使用APIはiOS 18以降とiOS 26のLiquid Glassで、27専用APIは使っていない。
iOS 27.2 SDKでビルドし、シミュレータ（iPhone 18 Pro Max）で動作を確認した。
iOS 26実機/シミュレータでの見た目、iPad、VoiceOver、Reduce Motionの実機確認は
未実施。モーフィングの滑らかさ・CPU/GPU負荷は自動テストでは判定していない。

## 検証

- `bitrig preview -platform iOS`: BUILD SUCCEEDED
- `capture-audio-picker.e2e.ts`: PASS（ライト/ダーク、作成シートが下から表示、音声ピッカー取消）
- `workspace-journal.e2e.ts --grep "insertion proposes"`: PASS（日付・イベント間の時刻）
- `workspace-journal.e2e.ts --grep "inline plus"`: PASS（行内＋から追加）
- `project-source-note-attach-order.e2e.ts`: PASS
- `source-ask-ai.e2e.ts`: PASS（再実行）
- `project-source-office.e2e.ts` / `project-source-recovery.e2e.ts`: PASS

ワークスペースの古いタブ名を前提にした`workspace-journal`の一部テストは
現行UIと一致せず失敗する（今回の遷移変更とは無関係）。実機の目視・動画確認は未実施。
