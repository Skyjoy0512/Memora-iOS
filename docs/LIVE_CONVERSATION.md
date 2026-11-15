# 日本語Live音声会話

LiveはAPIを使わないローカル専用の会話。通常のAsk AIで選んだクラウドモデルとは別に動く。
波形ボタンから始める。会話モデルが未導入なら初回セットアップを開き、ダウンロード操作を待つ。
導入完了後の「Liveを開始」で会話を始める。音声認識・会話生成・読み上げを端末内で処理する。

## 初回モデル導入

- 会話モデル: Volocalと同じQwen3.5-2B、GGUF Q4_K_S。
- モデル取得先: `bartowski/Qwen_Qwen3.5-2B-GGUF`、revision
  `7d26695454df6de5fbcce2e58681e62dae06ce43`。
- ファイル: `Qwen_Qwen3.5-2B-Q4_K_S.gguf`、1,327,696,992 bytes（約1.33 GB）。
- SHA-256: `55b574899b75180d084238ffbf5d3d165c568a3d73e1edbd3c826682a986c8d4`。
- `LocalVoiceModelStore`がURLSessionで取得し、別ファイルでサイズとSHA-256を検証してから確定。
  未完成・不一致のモデルは使わない。キャンセルや失敗は再試行できる。
- Application Support/LocalVoiceModelsへ保存し、ディレクトリをバックアップ対象から除外する。
  モデルのバイト列はSQLite/UserDefaultsへ入れない。初回取得だけインターネット接続が必要。
- `llama.swift 2.10327.0 / llama.cpp b10327`を固定する。この公式XCFrameworkは実機と
  シミュレーターを含む。より新しい2.10549.0にはシミュレーターsliceがなく採用しなかった。
- 日本語のSTTはiOS 26のDictationTranscriber / SpeechAnalyzer。AssetInventoryで
  日本語モデルを確認・必要時に取得し、prepareToAnalyzeで起動してからマイクを接続する。
- 日本語TTSはAVSpeechSynthesizerのPCM出力。Parakeet/PocketTTSの英語スタックは入れない。
- ライセンスは設定の一覧と`docs/THIRD_PARTY.md`に掲載する。

## 会話と制約

- `LocalLlamaContext`はVolocalのC APIラッパーをもとに、2048-tokenのコンテキスト、
  256-tokenごとの有界prefill、最大384出力token、キャンセル、UTF-8の部分byte結合を追加。
  原版のASCII以外を捨てる処理は採用しない。日本語と絵文字を保持する。
- `LocalVoicePrompt`は日本語の短い会話向け。文書や利用者の文字列に含まれるChatML制御tokenを
  エスケープし、質問のtokenが収まらない場合は参照文と履歴を段階的に減らす。
- 約1秒の発話の区切りで`MemoraModel.sendLocalVoiceChat`へ渡す。既存の会話テキストから
  最大8メッセージを使う。録音・記録検索・添付解析・個人メモリ・ツール実行はこの専用経路では行わない。
  参照資料0件と実際のローカルモデル名を回答詳細へ保存する。
- Liveから通常のsendAIChat、クラウドプロバイダー、URL自動取得、Web検索、MCPへは渡さない。
  ローカルモデルが使えなくてもAPIへフォールバックしない。
- 回答は通常の会話へ表示し、SQLiteの会話スナップショットと交換履歴へ保存する。
  ワークスペース世代・会話ID・リクエストIDを再確認し、古い応答は置換後の会話を変更しない。
- 回答中の発話は生成と再生へ割り込む。割り込み後、前のnative batchの解放を最大2秒待つ。
  共有AVAudioEngineのVoice Processingでエコーキャンセルを使い、TTSは句点単位に流す。
- 既存の下書き・添付・メンションは自動で送らず、通常の入力で確認する。
  添付やモデルのシートはLiveを一時停止する。Liveのモデルボタンは導入状態を表示する。
- 会話/ワークスペース変更、バックグラウンド、ストア保護、録音の開始で音声処理を停止する。
  録音が持つオーディオセッションを奪わない。音声による操作承認は行わない。

## 無反応の検出

「聞いています」は日本語認識の準備とマイクバッファ受信後にだけ表示する。
入力レベルは小さなViewだけで4Hz更新し、会話やコンポーザー全体を更新しない。
マイクのバッファ停止は3秒、音声が届いても認識結果が出ない場合は15秒で理由を表示する。
静かな待機、認識後の沈黙、AI生成・読み上げ中は認識停止と判定しない。
認識器の起動が30秒で終わらない場合も停止する（初回モデルダウンロードは別）。
実機コンソールの`[Live]`は処理段階とエラーdomain/codeのみ。
発話本文・AI本文・音声・資格情報をログに含めない。

## 検証

- `bash tools/checks/run-live-conversation-checks.sh`: 文の分割、日本語/絵文字、上限、古い
  セッション/応答の拒否、入力停止・認識停止・沈黙・生成中の判定。
- `bash tools/checks/run-local-voice-model-checks.sh`: 日本語/絵文字のUTF-8 byte分割、
  不完全/不正なbyte列、ChatML役割の注入拒否、コンテキストの文字数上限。
- `tools/checks/LocalVoiceNativeChecks.swift`: 固定GGUFを使う実native推論チェック。
  モデルはリポジトリ外のBitrig Builds/References/LocalVoiceへ取得し、サイズとSHA-256を検証。
  Mac上で日本語の実出力、複数batchのprefill、会話間のリセット、長すぎるpromptの拒否を確認した。
  出力形式・native処理のチェックで、回答内容の正確さの保証ではない。
- 旧版で利用者のiPhoneは「聞いています」のまま文字が出なかった。旧版の診断がないため、
  マイク経路か認識器のどちらが根因だったかは確定していない。
- シミュレーターの表示やMac上のLLM推論は、iPhoneでの音声往復の証拠ではない。
  モデル導入後のiPhoneでの発話→日本語認識→ローカル回答→読み上げ、割り込み、
  Bluetooth/イヤホン、着信・録音競合は実機での確認が必要。

追記: Bitrigのプレビュー上でも、実際の約1.33 GBダウンロードとSwiftのSHA-256検証が完了し、
「導入済み」および「Liveを開始」ボタンを確認した。会話モデルの読み込み後、プレビューの
日本語認識が対応音声形式を返さず停止した。モデル導入完了と音声往復の成功は別の検証。
Macのnative検証では「こんにちは。」を生成できた一方、算術の質問に誤答したケースもあり、
このテストを回答品質の保証として扱わない。

最終確認: iOS 27.2 SDKで `bitrig preview -platform iOS` と
`bitrig build -destination generic/platform=iOS` が成功（既存の警告11件）。
再起動後もモデルの導入済み状態を保持し、再ダウンロードを求めず読み込みへ進むことを確認。
UTF-8/プロンプト、Live制御/入力監視、既存コンポーザーレイアウト/提案保護、チャット構造8件の
チェックを通過。iPhoneへはこちらからインストール・起動しておらず、iPhone側のモデル導入と
実際の音声往復は未確認。
