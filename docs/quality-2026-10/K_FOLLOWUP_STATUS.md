# 2026-10-26: 到達点・未完了項目

総合プロジェクトは未完了。開始時にGitHub mainをfetchし、`cb23b3d`/cleanを確認。`23230af`以来の修正とA〜Gを再利用し、同じ問題を別実装で上書きしない。今回も実ユーザーデータの削除/再生成、本番変更、有料API実行、署名/Bundle ID/App Groups変更は行っていない。

## 完了条件ごとの状態

| 項目 | 実装・検証済み | 残る作業/外部境界 |
| --- | --- | --- |
| CI | 英語localeのassertionまで原因特定、両localeで厳密比較、GitHubコードcommit全6suite Green | 最新commitごとの結果は[CI](CI.md)とGitHub Actions。ホストCIはiPhone/実APIではない |
| 50秒問題 | 既知DeepSeek受信上限修正を維持、大量推論/仮想時間/実時計30〜180秒/SQLite/取消回帰Pass | 実ユーザーのjob ID/終了理由なし。同一原因・実ジョブ再発なしの証明は未達 |
| 要約速度 | bufferのホスト実測、大きいChat本文でmedian 56.1%減。4区間の並列scheduler/順序/失敗fixture | 総生成時間の実API改善率・品質/費用のA/Bは未検証。端末速度へ換算しない |
| 生成mode | 高速/標準/高精度を詳しさと分離。レビュー済みDeepSeekだけthinking制御、旧設定/job互換 | 既定は従来どおり。未知登録モデルや他社の推論設定は未検証として変更しない |
| 長文 | 高速opt-in最大2並列、全区間成功後の既存統合、各送信前の権限/入力再確認 | 意味境界の高度分割、部分結果の永続再利用、暫定本文プレビューは未実装 |
| 事実/引用 | 否定/条件/数値/原文IDを保持する既存promptと図解validator/fixtureを継続 | 実モデルの取りこぼし・推論ON/OFF品質、医療/商談等の人手正解評価はNot Run |
| IME | 本番editor/SQLiteで日本語置換・絵文字・結合文字・list/table・再起動E2Eを再実行Pass | 実機日本語keyboardのmarked text/候補確定操作はNot Run |
| 保存/復旧 | 実SQLite原子的commit/ABORT/再open、旧原文/summary/job保持。10,000件の実Meeting codecを計測 | 全量encode/同期commitの負荷は未解消。schema段階移行・off-actor準備と再検証の設計が必要 |
| ライセンス | Keychain成功後のみ状態変更、失敗注入/期限/再読込/旧code保持をPass | 実SecItem OSStatus・ロック状態・実機再起動・契約サーバー照合はNot Run。StoreKitとは別 |
| AskAI/Agent/Skill | 既存スコープ・承認・コスト・古いcontext/副作用抑止のproduction fixtureを再検証 | 実アカウントを使う全tool実行/副作用/再接続E2EはNot Run |
| MCP/OAuth | IP固定/TLS/HTTP/SSE/ID/取消/refresh CASの既存fixtureを再検証、制限を緩めない | HTTP/2専用・圧縮・複数IP failover・OAuth browser実サービスは未検証/制限あり。管理サービスには信頼backendの接続先/認証/監査/料金制御が必要 |
| RAG/記憶 | 27問でRecall/MRR維持、混入0.519→0.167、棄権1/5→5/5、権限失効/重複除外fixture | 混入は残る。実質問・holdout/意味検索・長期記憶大量データの実機品質は未検証 |
| UI | 生成modeはnative menu、Light/Darkと最大Dynamic Typeを実画面で確認。編集/要約のE2E | VO実音声、全Journal/workspace操作、全端末サイズ、Reduce Motion実機はNot Run |
| 全体性能 | JSON/SQLite/検索/streamingのホスト値と境界をD/H/Jに記録 | 起動/初期描画/scroll/frame/録音CPU電池/画像PDFOfficeピークの実機Before/AfterはNot Run |
| 外部接続 | [F](F_CONNECTIONS.md)の分類を更新。未接続を完成扱いしない | StoreKit/sign-in/TeamBackend/Memora server、署名/外部accountが必要な接続は未完了 |

## 次の順序

1. 実DeepSeekの診断照合と、許可された範囲で固定データの推論ON/OFF A/B（時間・正解/否定/条件・出典・token・料金）。課金の許可なしには実行しない。
2. 実機でOS continued processing/expiration/再起動、IME変換、録音と保存保護/容量不足、VOを確認。Simulator fixtureで代替済みとはしない。
3. 全Meeting保存負荷を、互換性・transaction・古いsnapshot排除を維持して改善。型/保存方式の大規模変更は計測と段階移行/rollbackの検証を先行。
4. 語彙RAGの残る誤混入を拡張評価、MCP実サービス互換性を安全な接続先・許可済みaccountで確認、未接続backendの別設計。

コードが存在すること、host Pass、Simulator Pass、実機 Pass、実API Passは別の状態として扱う。今回実施していない項目をPassや完了とは報告しない。
