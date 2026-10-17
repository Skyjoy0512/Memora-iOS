# 長期メモリの明示更新と矛盾解消

基準: main `5930c1a`。Swiftネイティブと既存SQLiteを継続し、外部サービス・依存追加・保存スキーマ変更はない。

## 監査と変更

従来は状態分類と単一記憶の改訂履歴が存在したが、競合した値を現在の情報として選ぶ専用操作がなかった。
また、競合検出がほかの記憶の状態だけを書き換え、その変更前の状態と更新日時を記録していなかった。
編集シートは開いた時点の値を保持する一方、保存・削除はIDだけを使い、途中変更を検出しなかった。

- `AIMemoryEditFields`: 既存のネイティブForm/Pickersを保ち、同じ項目のほかの記憶を表示する。
  「編集中の内容を現在の情報として確定」を利用者がオンにして保存すると、表示したほかの値を「過去の情報」にする。
  選ばない場合は従来どおり矛盾として保持する。200文字を超える編集は切り捨てず保存不可とする。
- `AIMemoryEditDraft` / `AIMemoryEditPlan`: 表示時の元の記憶・関連値を比較し、変更、削除、新規候補、workspace変更を検出したら保存しない。
  関連範囲はworkspace・subjectID・明示したpredicateの完全一致。「note」は一般メモなのでまとめない。
  過去・無効化済みの値は変更対象にしない。名前の類似や自然言語から自動で統合・事実確定しない。
- `AIMemory+Editing`: 状態の変更にも改訂を残す。過去にする値は元の出典・観測日・有効開始日・機微性・確認状態を保ち、
  有効終了日と更新日を設定する。従来と同じく各記憶の改訂は直近30件まで。過去にした記憶本体は削除しない。
- `MemoraModel+MemoryManagement`: 既存Memory extensionから保存管理を切り出し、本番の編集・削除ゲートをホストで検証可能にした。
  編集結果をSQLiteの単一documentとして同期保存し、成功後だけmodelを差し替える。復元中・保護中・古い編集シートからの保存/削除を拒否。
- `AIMemoryEditor`: 画面を再表示しても入力を初期化しない。保存元が変わったら編集を止め、開き直す案内を表示する。
  ワークスペースが変わるとシートを閉じる。過去の内容には当時の状態を併記する。
- `AIMemoryView`: 追加/削除の保存失敗を表示し、全削除のworkspaceを確認時の値に固定する。検索一致なしを空の記憶と区別する。
  自動利用は現在有効・確認済み・通常の機微性に限ると明記した。メモリOFF、既存FTS5検索、外部送信前の指紋照合は維持する。

## 検証方法

`bash tools/checks/run-memory-editing-checks.sh` は本番の編集plan、status/history処理、MemoryManagement extension、
AIRecordFingerprint、LocalStoreを使用する。MemoraModelのstored stateとpersistNowの入口は小さいfixtureとし、
書き込みと再読込は実SQLiteで実施する。実ユーザーのDB、APIキー、ネットワーク、Keychainには触れない。

対象: 明示確定/通常競合、変更前の状態/出典/有効期間、legacy semantic省略、機微情報、subject/workspace/predicate分離、
古い元値/関連値/新候補/削除/二重保存、復元/保護、200文字超/空/重複ID、SQLite再読込。
実SQLiteのINSERT拒否triggerで複数記憶の保存失敗を起こし、DBとmodelの双方が元の集合を保つことも確認する。
保存失敗中の削除・全削除、更新済みの記憶を古いシートから削除する経路も拒否する。

`AIMemoryEditingExampleView` はDEBUGの「状態と復旧UIを確認」→「記憶の更新（架空データ）」に置く。
本番の入力部品と編集planを使うが、状態は画面内のみで保存済みメモリには接続しない。

## 結果と未検証

- 専用 `run-memory-editing-checks.sh`: 成功。標準の `run-next-generation-checks.sh` にも追加した。
- `run-next-generation-checks.sh` / `run-motion-loading-checks.sh` / `run-optimization-checks.py`: すべて成功。
- `bitrig preview -platform iOS`: Debug成功、プレビュー起動。Release Simulatorビルドも成功。
  両方とも既存の警告11件、コンパイル/リンクエラーなし。
- Debug log: `2026-10-17T17-44-02-564eae54.log`。
  Release log: `2026-10-17T17-44-02-3daa217d.log`。
- Simulatorの架空データ画面で、現在/過去への変更と改訂件数、途中変更時の保存拒否を操作確認した。
  Light/Dark、最大アクセシビリティ文字サイズでの折り返しとスクロール、Reduce Motion有効時のスイッチ操作を確認。
  画面内の状態だけを操作し、保存済み記憶・会話・外部サービスは操作していない。
  確認開始時に見えていたLightのHomeへ戻した。UI確認は実AIMemoryEditor全体のE2Eではなく、共有する本番入力部品と編集planの確認。
- [操作前](qa/askai2/memory-updates/before-resolution-light.png) /
  [操作後](qa/askai2/memory-updates/after-resolution-light.png) /
  [途中変更の拒否](qa/askai2/memory-updates/stale-edit-rejected.png) /
  [Dark](qa/askai2/memory-updates/editor-dark.png) /
  [大きな文字](qa/askai2/memory-updates/editor-large-text.png)。
  操作前/後は同じ実装内での状態比較であり、旧バージョンとの外観比較ではない。
自動的な意味矛盾の判定、推論による記憶抽出、メモリサーバー/Embeddingは追加していない。
実アカウントのAI送信、実機VoiceOver/性能、実利用者のバックアップ復元は本fixture検証とは区別する。
