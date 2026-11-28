# 検証状況

| 対象 | 環境 | 結果と境界 |
| --- | --- | --- |
| 既存ナビゲーション・キーボード | iPhone 18 Pro Max E2E、開始点の変更時 | 4 件成功。今回の機能追加は別検証 |
| Keychain 書込と ChatGPT ビルド条件 | Mac ホスト、合成 Security 戻り値、4 コンパイル構成 | 成功。OS 実機の保護・失効・既存資格情報は未実施 |
| アカウント画面契約 | Python ホスト | 11 件成功。対話の見た目はシミュレータで別確認 |
| 同時取込・通信／保存失敗 | Mac ホスト・実 SQLite と一時ファイル | 24 同時コピー文、24 同時画像、32 の失効競合、SQL 失敗を確認 |
| 音声 Core ML・動画・プロジェクト原本 | Mac ホスト | 通過。実機録音、音声精度、クラウドは未計測 |
| SQLite 保存・性能 | Mac ホスト・合成 100/1千/1万/5万件 | 復元と ID 整合を確認。計測詳細は下記 |
| 既存データの移行・隔離 | Mac ホスト・実 SQLite | 退避／マーカー／削除で失敗する場合の rollback、競合した新しい原本の維持、旧データの再出現防止を確認 |
| バックアップ復元 | Mac ホスト・実ファイルと SQLite | 保護ディレクトリの作成を拒否した場合は未確定。旧形式・音声写真の復元・競合・ロールバックも通過。端末ロックは未確認 |
| 写真 OCR の派生データ | Mac ホスト・実ファイルと SQLite、認識結果は fixture | 差し替え、削除、復元、ロック、ワークスペース遷移、12 枚の処理上限と次回継続を確認 |
| 写真から記録を探す、既存のファイル検索 | iPhone 18 Pro Max 専用 E2E | 2件成功。実 Vision に合成画像を渡し、未訪問の写真の文字でヒットし原本削除後はヒットしないことを確認 |
| プロジェクトの5セクションとダーク表示 | iPhone 18 Pro Max 専用 E2E | 2件成功。記録、資料、参考資料、チャット、画像の切替と、画像から記録に戻る動線を確認 |
| 会話の再送保護 | Mac ホスト・純粋な来歴検査とスナップショット | 旧版／端末内の履歴は再送不可、採取済みの来歴・現行の許可・版が揃う場合のみ許可。実 API は未実施 |
| MCP の認証中断 | Mac ホスト・本番認証フローと模擬シート／通信 | 同時実行、名前の検証中の取消、遅れて届くシートの応答、交換中の取消を確認。保留中の別の認証には影響せず、現在の操作だけが資格情報を返す。実アカウントは未実施 |
| プロジェクト会話の出典を引き継ぐ場合 | Mac ホスト・本番送信ロジックと模擬モデル | 過去の回答に由来する写真も次の回答に根拠として残り、取り消し後の再利用を拒否。旧・復元履歴や端末内回答はクラウドに再利用しない |
| プロジェクトの時系列根拠 | Mac ホスト・実 FTS5、会話入出力 | 記録日と録音内の位置を分けた文脈、日付だけ変わった場合の差分更新、再オープン、旧引用のデコードを確認。実 AI が矛盾を解消できるかは未実施 |
| 記録日付き出典と所属変更 | iPhone 18 Pro Max 専用 E2E・合成履歴 | 出典に日付が表示され、別プロジェクトへ移った記録は拒否され、現所属の記録は文字起こしまで開いた |
| 写真の根拠と原本 | Mac ホスト、iPhone 18 Pro Max 専用 E2E | 対象記録・既存インデックスの抜粋検索、クラウドへの登録拒否、無関係な写真と置き換え済み写真の除外。プロジェクトと質問履歴から原画像を開き、削除後に拒否することを確認。端末内モデルの実推論は未実施 |
| ナビゲーション・画面端 | iPhone 18 Pro Max と iPhone 18 Pro の専用 E2E | 先行8件成功。追加4件では最大文字サイズの文字起こしと検索、Ask AI の候補と入力欄、ダーク表示、原画像を確認。幅402pt の iPhone 18 Pro でも同じ3件が成功し、固定見出しの下とキーボード上の領域で操作できた |
| 長期記憶の検索 | Mac ホスト・合成日本語11ケース | 適合10/10、取得10/10。人物と領域を限定し、更新と削除の反映を確認。実推論の事実性・回答品質は未計測 |
| プロジェクトの時系列横断 | Mac ホスト・実 FTS5、合成資料52件 | 適合9/10、取得9/9。方針変更前後の2件、監査資料を含む3件、更新・移動・削除を確認。記録日を明示した検索は対象日だけを取得し、日付だけの検索も成功。用途を指定しない日付表現では古い記録も1件返った。70回の再検索は p50 0.31 ms、p95 0.57 ms |
| 資料生成 | Mac ホスト・実出力と Quick Look | 65型の構造と書き出し。原本と Quick Look 14型、CoreGraphics 38型に描画差。Office での編集・再保存は未確認 |
| 統合品質ゲート | 固定コミットの Mac ホスト | `a794baac`、`54974876`、`2dc48020`、`c489bcfb`、`9b4454eb` は11/11成功（`9b4454eb` は `/Volumes/DevSSD/Development/Temp/memora-release-qa.3xymxQ/run/summary.json`）。以前の長時間 WAV の失敗は統合再実行と単独2回で再発しなかった |
| ジャーナル・録音・チャット E2E | iPhone 18 Pro Max 専用 E2E | `journal-failure`、`project-chat-citation`、`marketplace-discovery`、`recording-power`、`summary-recovery` が成功。ジャーナルのメモは空の日を選んで「記録を追加」から作成する。`capture-audio-picker` は音声取込のキャンセル後にアプリのアクセシビリティツリーが戻らず QA-08 として残す |
| 参考資料の作成 E2E | iPhone 18 Pro Max 専用 E2E | `project-source-note`、`project-source-note-attach-order`、`project-source-interruption`、`source-ask-ai`、`library-photo-ocr` が成功。ワークスペースのセクションはインラインの「参考資料」を押す。`project-source-photo`（写真ピッカーの確定ラベル）と `project-source-pickers`（閉じた後の空状態の文言）は QA-07 として残す |
| アクセシビリティツリーの欠落 | iPhone 18 Pro Max シミュレータ | `capture-audio-picker`（ピッカー取消後）、`background-summary`（起動直後）、`project-source-photo`（写真ピッカー再表示）、`project-source-pickers`（作成画面を閉じた後）、`summary-reading-accessibility`（記録詳細を開いた直後）、`ui-polish`（`keyboard` ノード）で、画面には正しいUIが出ているのにツリーが空または2〜3ノードになる。座標タップでは操作でき、再実行で消えることもある。アプリの停止ではない |
| 参考資料の作成 E2E（QA-07） | iPhone 18 Pro Max 専用 E2E | `project-source-photo` は保存失敗時に「資料を保存できませんでした。ストレージの空き容量を確認してください。」がエディタ内に出て、タイトル「Photo draft」と本文が残ることを確認（手順58〜61）。その後の写真ピッカー再表示は、スクリーンショットでは開いているのにツリーが2ノードのままで検証できない。`project-source-pickers` は閉じた後にツリーが3ノードになるが、スクリーンショットには「参考資料はまだありません／リンク・ファイル・メモをまとめられます。」が正しく出ている（環境要因） |
| 入力欄のフォーカス E2E（QA-06） | iPhone 18 Pro Max 専用 E2E | `capture-audio-picker` は取り消し後にアプリのツリーが空になるが、同じ画面で座標タップするとサイドバーが開き、スクリーンショットも正常だった。`background-summary` も起動直後に同じ3ノードのツリーで失敗し、再実行では成功した。どちらも描画と操作は生きているため、この環境のアクセシビリティツリーの不調として扱う。`sidebar-glass` 3件中2件成功。添付メニューから「コネクタ…」を開き「閉じる」で戻すと `添付を追加` がツリーから消える。`ui-polish` 2件中1件成功。外観をダークへ切り替えた後の `keyboard` 断言で失敗する。切り分け用に「入力欄へフォーカス→@候補を選択」だけを行う一時テストを実行したところ、フォーカス直後でも `keyboard` のノードが無く、このシミュレータのソフトウェアキーボード設定に依存すると分かった。キーボード断言だけではアプリの不具合と環境を分けられないため、未修正のまま残す |
| 添付シートの E2E（QA-06） | iPhone 18 Pro Max 専用 E2E | `sidebar-glass` 3/3成功。Ask AI の紙クリップは「チャットに追加」でチャット用シートを開くため、テストを現行の導線（最近の写真・閉じた後の下書き）へ更新した。入力欄と下書きは保たれている |
| UI・メニュー E2E | iPhone 18 Pro Max 専用 E2E | `answer-actions` 3件、`people-management`、`capture-menu-layout` 2件、`sidebar-glass` 2/3件、`ui-polish` 1/2件が成功。追加メニューは「録音する／音声を取り込む／ノートを追加」、資料の検索は文言で確認。起動時のマイク許可ダイアログは `launchMemora` が「許可しない」で閉じる。添付メニューを閉じた後の再表示と、候補選択後のキーボード保持は QA-06 として残す |
| ナビゲーションの再確認 | iPhone 18 Pro Max 専用 E2E | 保存形式と入力欄の変更後に `native-header` 4/4、`root-tab-navigation` 4/5 が成功。失敗は `keyboard` ノードが無いことによるもので、上のアクセシビリティツリーの項と同じ |
| ナビゲーション・コレクション E2E | iPhone 18 Pro Max 専用 E2E | `native-header` 4件、`root-tab-navigation` 5件が成功。`collection-polish` 4件成功。書類編集の破棄確認は iOS 27 のダイアログが破棄ボタンだけを描き、外側タップで編集を続ける仕様に合わせて検証した。検索の空状態は testID ではなく文言で確認する |
| マーケットプレイスの記事・検索 E2E | iPhone 18 Pro Max 専用 E2E | `skill-polish` 2件と `minimal-polish` 2件が成功。タブは「すべて／スキル／要約／コネクタ」のボタン、検索は `collection.search.input`、記事の節は「詳しい手順」。行本体のタップで詳細が開くようになり、テストも行を直接押す |
| コネクタ・カレンダー E2E | iPhone 18 Pro Max 専用 E2E | `calendar-context`、`gmail-connection`、`mcp-connection`、`notion-connection` の4件が成功。一覧は「…を追加・接続」で詳細を開き、アクセス説明は「アクセスと利用設定」を展開、管理はフッターの「接続」「コネクタを追加・管理」から開く。未接続でも「Ask AIで使う」を切り替えられるよう修正した |
| エージェント・チャット面 E2E | iPhone 18 Pro Max 専用 E2E | `agent-approval` 2件、`chat-surface` 3件、`agent-entry` 5件が成功。Ask AI の添付は `ai.composer.add`、折りたたみ時は入力欄の横・展開時は縦に並ぶ。サイドバーは設定ボタンで確認 |
| 参考資料・引用の E2E | iPhone 18 Pro Max 専用 E2E | `project-source-office`、`project-source-recovery`、`source-audio-citation`、`source-web-citation` の4件が成功。ワークスペースの5セクションはインライン表示、資料の本文は「原文／ノート本文」を開いて確認する。ノートの要約準備中は「その他」が無効になるため、有効化を最大60秒待つ |
| 要約の読み面 E2E | iPhone 18 Pro Max 専用 E2E | `adaptive-structured-summary`、`markdown-replacement` 2件、`summary-reading-accessibility`、`draft-protection` 2件が成功。共有シートを閉じた後や再起動後にアプリのツリーが外れる場合は `restartToLibrary` でライブラリから開き直す。`summary-reading` はポスター前提のため skip |
| 要約の判断・ポスター E2E | iPhone 18 Pro／Pro Max 専用 E2E | 判断の編集は「その他 › 要点・決定事項を編集」のシートで、保存・再起動後の復元・要約と文字起こしの不変・確認リンク非表示を確認。ポスター系4件は `FeatureFlags.isInlineSummaryPosterEnabled = false` のため理由付きで skip（旧ヘルパーでも同じ失敗で、今回の変更が原因ではない）。`meeting.tasks.add` は `adaptive-structured-summary` が引き続き検証する |
| 設定・待機・サンプルの E2E 更新 | iPhone 18 Pro Max 専用 E2E | 旧UI・旧文言で失敗していた7件を現行へ更新。`settings-polish` 5件（外観は `外観` Picker、サイドバーはマーケットプレイス／タスク／資料／人物と設定）、`waiting-evidence`（`ai.waitingStatus` の「考えています」）、`summary-sample`（Markdown 本文とノートの注意書き）、`summary-one-tap`（標準のAIの Picker、`要約し直す`、送信先の表記）が成功 |
| サンプル画面の E2E | iPhone 18 Pro Max 専用 E2E | `screen-review-samples` は、浮遊する入力欄の下にある行をタップしてタブ列に当たっていた。行を安全な範囲へスクロールしてから押すよう修正し、成功（`tests/screen-review-samples.e2e.ts`）。アプリ側の不具合ではなく、他のテストと同じ操作条件に揃えた |
| 画面・体験の E2E 棚卸し | iPhone 18 Pro Max／Pro 専用 E2E | `screen-polish` 8件と `experience-polish` 9件が全17件成功。旧ラベルを現行の導線（記録を追加、追加メニュー、タスク、参考資料、AIで資料を作る、日本語の日付、`auth.continueLocal`）へ更新。作業中にタスク画面の大きなタイトルが「未完了／完了」に重なり「完了」を押せない実不具合を見つけ、インライン表示にして修正した。タスクの作成・完了・再起動後の保持は幅402pt の iPhone 18 Pro でも成功 |
| Bitrig iOS Debug/Release | シミュレータ向けビルド | 日付付き出典まで Debug／Release 成功。写真の根拠まで Debug 成功。記録単位の保存と Accelerate 化の後も Debug 成功。実アカウント・実機は未実施 |
| 記録単位の保存 | Mac ホスト・実 SQLite・合成100/1千/1万/5万件 | 切替（行・manifest・旧BLOB退避）、1件編集で1文書だけ更新、並び替え・追加・削除、破損行・別IDの行・欠落・余剰行の拒否と旧BLOBへの復帰、書込失敗時のロールバックを確認。並列復号でも同じ内容・順序・digest 検証が通る。読込は5万件 221 ms（BLOB 353 ms、38%短縮）。iPhone 実機の移行と転写入り実データは未実施。`tools/checks/run-meeting-archive-checks.py` |
| 音声信号の一致と速度 | Mac ホスト・合成波形 | Accelerate の二乗和・ピーク・しきい値カウントが素の計算と一致。512/4,096/8,192 で間引きループを上回るか同等。非有限値は検出 |
| VAD の実行先 | Mac ホスト・同梱モデル | manifest 検証（欠落を拒否）、4実行先の読込・推論・出力一致を確認。実機の電池・熱は未計測 |
| 並列復号の実機相当比較 | iPhone 18 Pro Max シミュレータ・Release・合成2,000件 | 直列 138〜186 ms、512件ずつ並列 62〜69 ms（起動準備完了まで、各4〜5回）。Debug では並列が約149 msで、Release の数値を使う |
| 旧形式からの移行（シミュレータ） | iPhone 18 Pro Max シミュレータ・合成2,000件 | 起動後の保存キューで移行し、`memora.meeting.<id>` 2,000件・manifest・`memoraMeetings.legacy` を作成、旧 BLOB を削除。Debug は移行 2,044 ms、Release は移行 506 ms・起動は旧 BLOB 103 ms・行 62〜69 ms |
| 並列復号後の記録読み込み | iPhone 18 Pro Max 専用 E2E | `recording-lifecycle` 3件、`adaptive-structured-summary`（要約・根拠・転写の往復）、`library-photo-ocr`（写真付き記録の種込と検索）、`draft-protection` 2件、`markdown-replacement` 2件が成功 |
| 保存形式に依存する E2E の更新 | iPhone 18 Pro Max 専用 E2E | `memoraMeetings` を直接読み書きしていた7ファイルを、manifest と `memora.meeting.<id>` を扱う `readMeetings`／`writeMeetings` に移した。`recording-lifecycle` 3件、`markdown-replacement` 2件、`draft-protection` 2件、`project-chat-citation` 1件、`adaptive-structured-summary` 1件、`background-summary` 1件（再実行で成功）、`library-photo-ocr` 1件が成功 |
| 記録単位の保存（実機相当） | iPhone 18 Pro Max シミュレータ・実コンテナ | 画面確認用サンプル8件を追加し、再起動後も一覧に出て8件とも開けた。`documents` に `memora.meeting.<id>` が9件（32バイトの SHA-256 + payload）と manifest が入り、旧 `memoraMeetings` は無い（新規インストールのため退避対象なし）。旧形式からの移行はホストで検証 |
| 統合品質ゲート | Mac ホスト・固定ツリー | `ef766f66` で12/12成功。12番目の `performance-contracts` は信号演算の一致と速度、記録単位の保存契約、VAD の検証と実行先を確認する |

## SQLite 合成データの計測

9 回の中央値、音声ファイルなし、20 文字起こし断片／件。実 SQLite、ホストの並行負荷あり。バイトは論理 BLOB サイズまたはホストプロセスの最大 RSS。

| 件数 | 1件編集で再書込する BLOB | JSON encode ms（変更後） | SQLite 書込 ms（前 → 後） | 再オープン・読込・decode ms（後） | 書込区間ピーク RSS（前 → 後） |
| --- | ---: | ---: | ---: | ---: | ---: |
| 100 | 607,504 | 4.68 | 0.59 → 0.65 | 5.62 | 14.4 → 15.7 MB |
| 1,000 | 6,075,904 | 47.34 | 17.58 → 18.66 | 53.49 | 59.3 → 59.6 MB |
| 10,000 | 60,768,904 | 467.86 | 108.43 → 112.08 | 520.72 | 475.5 → 415.0 MB |
| 50,000 | 303,888,904 | 2,362.69 | 842.26 → 841.12 | 2,626.71 | 2,038.8 → 1,934.2 MB |

5万件をメタデータのみで計測した場合は、約67.34 MB、encode 388.84 ms、SQLite 119.51 ms、再読込 382.29 ms。現行の全件書込は残り、ホストで一貫した時間短縮は観測していない。iOS 冷起動、MainActor の固有時間、実機電池・発熱は未計測。

### 記録単位の保存方式の比較

同じ合成記録と SQLite 設定で方式ごとに9回測定。記録単位は既存のストアで1件を1キーに分けた比較用の設計。アプリの保存方式は全件 BLOB。

| 件数 | 全件 → 記録単位の JSON バイト数 | SQLite 書込中央値 ms（全件 → 記録単位） |
| --- | ---: | ---: |
| 100 | 607,504 → 6,087 | 0.674 → 0.041 |
| 1,000 | 6,075,904 → 6,088 | 22.11 → 0.055 |
| 10,000 | 60,768,904 → 6,089 | 109.62 → 0.032 |
| 50,000 | 303,888,904 → 6,090 | 841.34 → 0.040 |

5万件の記録単位方式で全件を再ロードすると、SQLite 読込 398.39 ms、JSON デコード 3,059.40 ms。書込の細分化と併せて、起動時はページ単位で読む設計が必要。ファイルシステムの実書込量、実データの移行、iOS 上の効果は未測定。

### 記録単位への移行リハーサル

Mac ホストの合成100・1千・1万・5万件。実 SQLite と本番の記録デコーダーを使用。元 BLOB、順序、ID、添付参照を比較し、既知のファイル内容が変わらないことを確認。別プロセスの途中終了、取消、SQL の失敗、競合書込、検証中の行改変、添付欠落、ID 重複も検証した。再実行で5万件のメタデータ約31.2 MBを50バッチに分け、準備943 ms、検証962 ms。本番の切替と長い文字起こしを含む移行は未実施。

検証済みチェックポイントからの読み込みは64件単位で、ページのダイジェストと行の改変・欠落・競合・取消を検出する。5万件の温キャッシュ5回の中央値で、先頭ページ0.78 ms、末尾付近0.70 ms、全件の読み込みとデコード333 ms（ホスト）。アプリの保存経路はまだ全件 BLOB で、この読み込みは接続していない。

### 長時間音声

1・3・8・24時間の合成 AAC は、実装の AVFoundation 書き出しと時刻補正、SQLite チェックポイントを通過。24時間相当は96チャンク、63.866秒、ピーク RSS 224.73 MiB。認識器は fixture。 [測定条件と全結果](../AUDIO_MEASUREMENT.md#長時間保存音声のホスト計測2026-11-25)
