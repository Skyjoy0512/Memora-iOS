# 職業・用途・話者情報の拡張

## 実装計画と依存関係
1. 職業・用途カタログ、複数選択と主職業、既存ユーザーの設定移行。設定はUserDefaults、記録はSQLiteのまま。
2. 既存IDを保持して用途テンプレートを追加。推薦は順序のみで、全テンプレートの利用を制限しない。
3. 手動テンプレート > 記録の用途 > 内容 > 職業推薦 > 詳細な概要。クラウドの分類は要約と同じリクエスト、端末内はローカル推薦にフォールバック。
4. 詳しさ・表示順、構造化セクション、要約履歴と復元。既存Markdown編集・音声を保つ。
5. FluidAudioの固定バージョンの公開APIとモデル利用条件を確認し、オンデバイスの声登録・録音後解析に接続。
6. 区間の重なりで文字起こしへ対応付け、手動の話者修正を保持。本人識別は互換モデルかつ検証した判定基準がある場合のみ。

## 変更対象
既存: MemoraModel、Templates/Processing/Meetings拡張、SummaryTemplateCatalog/MarketTemplate、
SummaryGenerationSheet、SummaryPrompt、MeetingSummarizer/OnDeviceSummarizer、Meeting/TranscriptSegment、
Settings/Onboarding、VoiceProfileView、バックアップで共有される記録形式。
追加: Occupation/UseCase/Profileカタログ・設定画面、要約設定/履歴/セクション、
話者処理サービス・端末内プロフィール保管・区間結合と回帰チェック。

## 保護する境界
- 原音声・原文を削除や再文字起こしで置き換えない。
- 声の特徴量と職業設定はチーム・AI・記録バックアップへ自動送信しない。
- ダウンロード/クラウド生成は明示操作だけ。未接続・モデル欠落・判定未調整を成功扱いしない。
- SDKのライセンスとモデルの利用条件は別々に確認する。
- Watchアプリ・本人識別精度・業務上の法的適合性は別途検証する。

## 状態
### 2026-10-11: 職業と要約テンプレートのUX連動
- 以前は職業の推薦が一覧の順序にしか反映されず、固定方式の既定が「詳細な概要」のままだった。手動指定のない既定を、主職業の最上位推薦から解決するよう変更。複数職業は主職業を優先し、すべて外すと詳細な概要へ戻る。
- 職業/主職業の明示変更時、手動指定がなければおまかせにする。手動テンプレートIDが保存されていれば保持する。「詳細な概要」を手動指定した場合もIDを保存して職業追従と区別する。未存在の手動IDは勝手に別職業形式へ変えず、詳細な概要にフォールバック。
- 仕事・活動画面に現在の基本形式、手動指定の説明、職業連動に戻す操作、要約スタイルへの導線を追加。要約スタイルには「仕事・活動に合わせる」と基本形式、職業変更への導線を追加。テンプレート詳細の既定指定は固定方式を有効化し、解除は職業連動のおまかせへ戻す。
- 要約シートのカスタム生成は、その記録の用途/内容/職業から解決された形式を選択済みにする。おまかせのクラウド生成には基本候補名を表示し、内容分類は従来と同じリクエストで行う。手動形式・明示用途を優先し、仕事以外の記録も形式を切り替えられる。
- 新しい永続化スキーマは追加せず、既存の職業プロフィールと既定テンプレートIDを再利用。過去の記録・履歴・詳しさ・AIエンジン・声プロフィールは変更しない。追加API呼び出しなし。
- 回帰項目: 美容師/介護士/電気工事士の既定、主職業変更、手動指定（詳細な概要含む）の保持、職業解除、再読込、欠落ID。実際のLLMによる形式選択品質は別途確認が必要。
- 変更ファイル: `MemoraModel+Personalization.swift`、`MemoraModel+Templates.swift`、`OccupationSelectionView.swift`、`SummaryStyleSettingsView.swift`、`SummaryGenerationSheet.swift`、`SummaryTemplateDetailView.swift`、`SummaryTemplateMarketplaceView.swift`、`SummaryTemplateSelector.swift`、`SelfChecks.swift`、`tools/checks/PersonalizationChecks.swift`、本書、`IMPROVEMENT_BACKLOG.md`。

第1段階: 16カテゴリー・116職種・19用途、複数選択/検索/主職業/自由入力、任意オンボーディング、推薦一覧と19テンプレートを追加。既存の23市場テンプレートIDを維持。旧ユーザーは固定方式、新規はおまかせを初期値とする。設定変更は過去の記録を変更しない。

`bitrig build -destination selected`: 成功。既存のRecordStore/AutoLocationLogger/メタデータ抽出の警告5件は対象外。
実機未検証の項目は未検証のまま扱う。以下の第2・第3段階で生成パイプラインと音声解析への接続を進めた。

第2段階: 要約シートに用途・詳しさ・クラウド送信確認を追加。手動指定を最優先し、用途指定時は自動分類を使わない。既存ユーザーの固定方式は維持する。おまかせ時のクラウドは既存の要約リクエスト内で候補から分類し、分類用の追加APIを呼ばない。端末内は内容ルール・職業推薦にフォールバックし、その旨を表示。分類の構造化データが不正な場合はMarkdownだけ保持し形式を確定しない。タスク抽出もしない。

要約履歴はMeetingに追加しSQLite/記録バックアップへ保存。再生成・復元前の手動編集と旧要約も保管し、原音声・原文は変更しない。構造化セクションは実際のMarkdownの見出しから抽出し、元発言へのリンクは一意な文字一致がある場合のみ。市場テンプレートの端末内生成は実際の生成結果を各見出しに整理する。要配慮・人物テンプレートは自動Webhook配信を抑止する。

検証: PersonalizationChecks成功（16カテゴリー、116職種、ID参照、推薦順、重複、保存、旧テンプレートのデコード、初期値移行）。SummaryPersonalizationChecks成功（美容師/スタッフ会議/介護/工事/休日の5例、曖昧内容、見出し解析、旧Markdown）。第2段階のビルド成功、既存警告5件。実際のクラウド応答品質・長い入力・実機の端末内AIは未検証。

## 第3段階: 音声処理・プライバシー

### 実装した処理
- FluidAudio 0.17.7をSPMのexactVersionで固定。画面・モデルはSpeakerDiarizationServiceを経由し、具体SDKはFluidSpeakerDiarizationServiceに閉じ込めた。
- 固定モデルrevisionは `df2625ac79a7ac6b65ad868fee6d80f320da4232`。25ファイル、21,634,526 bytes。利用者が確認した時だけ取得し、サイズとSHA-256またはGit blob SHA-1を検証する。欠落・改変時は処理を拒否し、通常の録音・文字起こしは利用できる。
- OfflineDiarizerManagerを録音後に実行。streaming用SpeakerManager/initializeKnownSpeakersをオフラインへ流用していない。
- 本人登録と会話解析の両方で、Community-1のchunkEmbeddings.embedding256を使用する。SDKのspeakerDatabaseや区間embeddingは128次元PLDA空間なので、声登録との比較には使わない。
- 各匿名話者の256次元embeddingを平均・L2正規化。登録済み特徴量とはモデルID・revision・次元一致の場合だけcosineを計算する。数値を本人確率として表示せず、未調整のしきい値で「自分」にしない。
- 文字起こし詳細に実際の解析ボタンと結果を追加。設定「文字起こし後に話者を解析」は初期オフ。オンかつモデル保存済みなら新規の文字起こし後に解析する。モデル自動取得や再文字起こしは行わない。
- SpeechAnalyzerの実際の発言終了時刻を保存。話者区間が発言全体を覆い、短すぎず、話者競合がない場合のみ匿名ラベルを付ける。終了時刻がない旧データ・テキストのみのクラウド結果では自動割り当てを行わない。
- 手動で確認した話者は再解析でも維持。旧形式のspeakerIsCertain=trueも確認済みとして保持する。ラベル修正で他人の特徴量を恒久登録しない。
- 話者ラベル・開始/終了時刻をSQLiteの記録に保存。要約へ話者付き原文を渡し、本文の従来のインライン編集と時刻ボタンからの原音声再生を維持。
- 記録や原文が処理中に変わった場合は古い結果を適用しない。要約・文字起こしと話者解析の競合を防止する。解析失敗時も原文・音声は保持。

### 声の登録と安全な保存
- 任意の同意、録音開始/停止、入力音量、20〜40秒の案内、40秒の自動停止、サンプル確認、再録音、モデル準備、特徴量生成、再登録/無効化/削除を既存Formに統合。
- 10秒の録音UX下限は精度保証ではない。SDKの最低発話量、実際の音声エネルギー・ピーク・検出話者数を確認し、無音・検出された複数話者・クリッピング候補を拒否する。
- 騒音の定量判定は未実装（noiseAssessmentAvailable=false）。モデルの誤分離・短い別人発話の見落としを含むため、複数人混入が必ず検出できるとは保証しない。録音時間による本人識別精度の保証もない。
- SpeakerProfileに本人ID・同意日時・モデルID/revision・次元・発話量・音質メタデータ・有効状態を保存。
- 特徴量を含むプロフィールJSONはAES-GCMで暗号化し、Complete File Protection付きファイルへ。256-bit鍵はWhenUnlockedThisDeviceOnlyのKeychain。ログへベクトルを出力せず、クラウドAIやチームへ渡さない。
- SQLiteにはUUID・モデル情報・有効状態だけのSpeakerProfileReferenceを保存。参照されていないファイルは照合に使わない。SQLiteの参照保存が成功してから新プロフィールを有効化する。
- 登録元音声は初期設定で生成後に削除。「音声も残す」を明示選択した場合のみ既存VoiceSamplesへ保持。旧プロフィールの特徴量・旧サンプルも再登録時に整理。
- 削除はまず永続的な失効フラグを設定。ファイル/Keychain削除に失敗しても再起動後に古い特徴量を再利用しない。削除の再試行を表示。
- 特徴量・サンプル・モデルは端末バックアップ対象外。Memoraの既存バックアップにも特徴量は追加していない。別端末への移行後は再登録が必要。設定・通常の記録の移行方式は変更しない。

## 要件別の結果（依頼の報告項目1〜25）

| 項目 | 結果 |
| --- | --- |
| 1 実装した機能 | 職業/用途設定、推薦、19形式、おまかせ選択、詳しさ、要約履歴、構造化見出し、実SDKを用いた声登録・匿名話者解析、手動修正、任意の自動解析 |
| 2 変更ファイル | 本書末尾に全一覧。既存の録音エンジンやストアを置換せず拡張 |
| 3 追加ファイル | 本書末尾に全一覧。データ/画面/音声サービス/チェック/ライセンスを分離 |
| 4 職業 | 16カテゴリー・116職種。カタログJSONで管理。検索・複数選択・主職業・自由入力・未選択・任意オンボーディングに対応 |
| 5 テンプレート | 新規19形式。既存23市場IDと4標準形式、ユーザー作成/インストール済み形式を保持。既存クレーム対応はIDを保って抽出ルールを補強 |
| 6 推薦 | 主職業から順に他の選択職業を統合しIDで重複排除。おすすめは順序だけに反映し、他の形式を隠さない |
| 7 自動選択 | 明示テンプレート > 明示用途 > 内容 > 職業推薦 > 詳細な概要。クラウド分類は要約と同じリクエスト。端末内は確認可能なキーワードの一致にフォールバックし、曖昧なら無理に分類しない |
| 8 詳しさ | 簡潔/標準/詳細を独立設定し生成プロンプトへ。端末内の区間整理にも適用。原音声・原文・過去の要約は変更しない |
| 9 動的表示 | 生成された見出し順に共通Markdownと情報カードを表示。「要約の項目と原文」でセクション内容と一意な原文一致へのリンクを確認。元のブロック編集も維持 |
| 10 音声SDK | FluidAudio 0.17.7（公開APIを解決済みパッケージのソースで確認）。Eagle/pyannoteAIは比較のみで未導入 |
| 11 モデル/ライセンス | Community-1固定revision。対象モデルはCC BY 4.0、SDKはApache-2.0、FastclusterはBSD-2-Clause。出典・全文・第三者告知を同梱 |
| 12 商用条件 | 確認したライセンスの表示・出典・変更告知を維持する方針。旧legacyモデルは対象ライセンス外なので未使用。正式な業務記録や法的適合性を保証しない |
| 13 登録方式 | iPhoneマイクの既存VoiceEnrollmentServiceを再利用。自由発話または例文。任意で1〜3件の録音をまとめて登録し、各音声で品質確認と実モデルのembedding生成 |
| 14 特徴量保存 | 端末内AES-GCM + Keychain + File Protection、SQLite参照、バックアップ対象外、失効優先の削除 |
| 15 話者分離 | OfflineDiarizerManagerの実際の区間とchunk embeddingsを使用。通常録音/インポートの共通音声URLを入力にする |
| 16 本人照合 | 同じ256次元モデル空間でcosine計算。モデル不一致・無効プロフィールは利用しない |
| 17 本人判定 | 自動「自分」確定は未実装。検証済みしきい値がないため匿名のまま。確率表示や認証利用はしない |
| 18 ラベル修正 | 既存の話者編集シートで本人/名前を確認。区間単位または同じspeakerID全体へ適用し保存。恒久声登録と分離 |
| 19 テスト | 下記の純Swiftチェック、アプリSelfChecks、シミュレーターUI、固定モデルダウンロードとCore ML無音解析 |
| 20 iPhone実機 | 未検証。iPhone 14 Pro Max/iOS 26の録音・音質・メモリ・発熱・FAR/FRRは別途確認が必要 |
| 21 API費用 | 分類専用APIなし。音声は端末内で従量課金APIなし。クラウドは利用者の既存設定と生成操作を尊重。ただし候補一覧で入力トークンが増え、長い記録の分割要約は既存経路の複数呼び出しを伴う |
| 22 容量/メモリ | モデル約21.6MB、取得前に約65MB超の空きを確認。プロフィールのベクトル自体は256×Float32=1KB、実保存はJSON/暗号化分増える。SDK/NeMoバイナリもアプリ容量を増やす。実機ピークRAM/電池/長時間解析は未測定 |
| 23 既存機能 | Journal/Files/Tasks/Ask AIのナビゲーションを変更しない。記録はSQLite、設定はDefaults、メディアはファイルのまま。旧要約/カスタムテンプレート/原文を保持 |
| 24 未実装/未検証 | 自動本人確定、実音声の精度、ノイズ定量判定、複数回サンプルの精度改善効果、Watchアプリ、チーム媒体同期、正式業務適合性、実プロバイダーの要約品質 |
| 25 次の候補 | 同意取得した日本語評価データによるFAR/FRR、登録発話量/しきい値の調整、実機マイク/BT比較、モデル配布容量削減、原音声ハッシュと編集履歴 |

### カテゴリーと職種数
| カテゴリー | 職種数 |
| --- | --- |
| オフィス・ビジネス | 10 |
| IT・エンジニアリング | 8 |
| 美容・理容 | 7 |
| 医療 | 8 |
| 介護・福祉 | 7 |
| 建設・職人 | 9 |
| 製造・工場 | 7 |
| 小売・販売 | 7 |
| 飲食・サービス | 7 |
| 運輸・物流 | 6 |
| 教育・保育 | 8 |
| 農業・一次産業 | 5 |
| クリエイティブ | 8 |
| 公共・専門職 | 7 |
| 学生・研究 | 6 |
| 日常生活・その他 | 6 |

全職種・用途・推薦IDは `App/Resources/OccupationCatalog.json` に収録。設定変更で過去の要約を自動再生成しない。

### 追加テンプレート（IDを固定）
| ID | 表示名 |
| --- | --- |
| work.customer-chart | 接客カルテ |
| work.treatment | 施術記録 |
| work.customer-handover | 顧客引継ぎ |
| work.care | 介護記録 |
| work.shift-handover | 申し送り |
| work.incident | 事故・ヒヤリハット |
| work.daily | 作業日報 |
| work.site | 現場報告 |
| work.inspection | 点検記録 |
| work.customer-record | 接客記録 |
| work.learning | 講義・学習ノート |
| work.journal | ジャーナル・ライフログ |
| work.technical | 技術・制作メモ |
| work.delivery | 配送記録 |
| work.education | 授業・活動記録 |
| work.consultation | 面談・相談記録 |
| work.growth | 生育・飼育記録 |
| work.research | 研究・実験メモ |
| work.shopping | 買い物・予定メモ |

新規19形式は自動タスク抽出を無効化。希望と提案・観察と推測を分離し、不明を補完しない。個人情報・要配慮形式と形式未確定のおまかせ結果は自動Webhook配信を抑止。利用者が設定済みの常駐エージェントは既存のBYOK処理のままなので、機微情報で使う場合はその設定も確認すること。正式な医療記録/守秘義務対応/ハラスメント認定/法的証拠を保証しない。

## 比較した音声技術と採用判断
- 採用: FluidAudio + Community-1。オフライン解析と互換embeddingを利用でき、SDK/対象モデルの表示条件を確認できた。音声を送信せず、新たなAPI費用も作らない。モデル由来の精度と実機負荷は別途評価する。
- Eagle: [iOS Quick Start](https://picovoice.ai/docs/quick-start/eagle-ios/)にSwift SDK、声登録/識別、AccessKeyを確認。登録はSDKの進捗判定に従う方式。企業向け契約・利用量課金を確認する必要があるため今回は未導入。確定料金は取得していない。[公式FAQ](https://picovoice.ai/docs/faq/general/)
- pyannoteAI: [Identification API](https://docs.pyannote.ai/api-reference/identify)にvoiceprintによるクラウド識別を確認。音声送信・API契約・保存ポリシー・料金の追加確認が必要なため未導入。日本語実会話の識別精度は確認していない。
- [FluidAudioの公開版](https://github.com/FluidInference/FluidAudio/tree/v0.17.7) / [モデルNOTICE](https://huggingface.co/FluidInference/speaker-diarization-coreml/blob/df2625ac79a7ac6b65ad868fee6d80f320da4232/NOTICE.md) / [モデルPROVENANCE](https://huggingface.co/FluidInference/speaker-diarization-coreml/blob/df2625ac79a7ac6b65ad868fee6d80f320da4232/PROVENANCE.md)。Core ML変換の変更がある。リポジトリの歴史的な変換手順まで完全に再現可能と確認したわけではない。
- SDKのNeMoテキスト処理バイナリはSPM依存としてリンクされるが、本機能ではASR/TTSを呼ばない。対応するライセンス・NOTICEも同梱。削減するならSDK製品の分割/配布構成を別途検証する。

## 検証記録と限界
- `PersonalizationChecks`: 成功。16/116件、推薦ID、検索、美容師/介護士/電気工事士の推薦、重複排除、プロフィール保存、旧形式、初期値移行。
- 初期の要約設定を移行時に一度保存し、新規ユーザーがオンボーディングを終えて再起動しても「おまかせ」を維持することをチェック。既存ユーザーの固定方式も維持。
- `SummaryPersonalizationChecks`: 成功。指定の美容/スタッフ会議/介護/工事/休日の5例、曖昧内容、見出し、旧Markdown。
- `SpeakerProcessingChecks`: 成功。embedding数学、モデル不一致、無効化、単一話者/重なり/話者交代/欠落区間/短い発言、手動修正、旧形式の確認済み名前の保持、プロフィールCodable。
- `SummaryEvidenceChecks`: 成功。原文一意一致のみ、曖昧/別表現/無効時刻/否定や数値の取り違えの防止。
- `SummaryLayoutChecks`: 成功。決定・アクションのある話題を先頭に、時系列設定では発言順に、明示の時系列議事録は時刻順を維持。
- アプリSelfChecks: シミュレーターで「Personalized summary compatibility: 成功」を確認。旧記録と要約履歴の読み戻しを含む。
- シミュレーターUI: 設定・職業一覧・美容師検索・選択/主職業を確認し、選択は未設定に戻した。モデル取得確認→25ファイルの取得・検証→保存済み表示を確認。
- 実モデル: 無音10秒をOfflineDiarizerManagerへ渡し、公開SDKのnoSpeechDetectedまで実行できた。これはモデルロード/セグメンテーションの確認であり、embedding推論・声登録・日本語複数話者精度の検証ではない。
- Debugビルドは各段階で成功。既存RecordStore/AutoLocationLogger/メタデータ抽出の5警告は本作業の対象外。
- ReleaseのiOS Simulatorビルドも成功（既存警告4件）。最終Debugのモデルチェック画面で「モデル読み込み・無音の検出に成功」を確認。自動解析トグルの初期オフも確認。
- 仕事・活動/要約方式/自動話者解析は端末設定として永続化し、手動の記録バックアップへは追加していない。設定の端末間移行は別工程。
- 実際のクラウド要約・端末内LLMの生成品質、VoiceOver/Dynamic Type実操作、声の録音・鍵の実機保護・再登録/削除のE2E、バックアップ実復元は未検証。通常の記録を試験のために変更していない。
- 音声識別シナリオEの自動「自分」は未完了。実機・同意済み評価音声によるFalse Acceptance/False Rejection測定が次の必須工程。
- WatchConnectivity/Watch長時間録音は未実装。音声解析サービスはファイルURLを受け取り、通常録音とインポートで共通化済みなので、将来の入力元を録音エンジンに密結合していない。Watch転送後の既存インポート処理再利用は今後の実装。

## 変更ファイル一覧

### 追加工程：複数サンプル登録と保存の回帰検証
- 1件あたり最大40秒、任意で最大3件。これは処理量を抑えるUX上の上限で、モデルの精度保証・必要発話量を示す値ではない。各サンプルを個別に解析し、単一話者・発話・音割れ・有限な特徴量を確認する。どれか1件が失敗したら、既存プロフィールを置き換えず番号と理由を表示する。
- モデルID/revision/256次元が一致するベクトルだけを、サンプル単位でL2正規化して平均・再正規化する。音声の長さでは重み付けしない。RMSは音声時間に基づくエネルギーから集計し、各サンプルの品質値と登録件数も暗号化プロフィールに保持。旧形式はサンプル1件として表示する。
- 各録音で話者1人を検出しても、録音間で同じ本人であると証明できるわけではない。すべて自分だけで録音するよう明示し、同一人物判定のしきい値は追加していない。複数サンプルの精度改善は未検証。
- 一時サンプルの追加・個別確認・削除・録り直し、解析中の件数表示・中止に対応。画面を閉じたら未登録の音声を削除し、削除失敗分は既存の次回起動時の整理対象にする。
- 初期設定では全登録音声を特徴量の保存後に削除する。音声保存の明示選択がある場合は最後の1件のみ保持することをUIで説明。既存VoiceProfileの単一ファイル参照・バックアップ方式は変更しない。
- SpeakerProfileStorageは保存先・Keychainサービス・Defaultsを注入できる内部実装に分離。製品の保存パスと鍵名は維持する。DEBUGチェックはUUID付きの別フォルダー・別Keychainサービス・別Defaultsを使い、製品のプロフィールや鍵に触れない。
- 純SwiftのSpeakerProcessingChecksに複数サンプル統合・数量上限・モデル不一致・旧プロフィール・無効な品質値・正規化によるサンプル等重みを追加して成功。既存の職業・要約・根拠・表示順チェックも回帰検証して成功。
- 暗号化保存チェックではAES-GCM往復・再生成nonce・改ざん拒否・UUID不一致拒否・鍵消失・削除・失効後の明示有効化・File Protection・バックアップ除外を確認する。合成ベクトルを用いる保存の検証であり、本人識別精度の検証ではない。
- 実行したBitrigシミュレーターでFileAttributeKey.protectionKeyはnilだった。この環境ではロック時のファイル保護を成功扱いせず、チェック名にも「lock protection untested」と明示する。実機DEBUGでは属性がcompleteであることを必須にする。実機のロック中の読み取り拒否・バックアップ実復元は別途検証が必要。暗号化・鍵の属性・改ざん・削除のチェックはシミュレーターでも省略しない。
- 当工程のDebugビルド成功（既存警告5件）。シミュレーターで「Speaker profile storage (lock protection untested): 成功」と要約互換チェック成功を確認。AES-GCM・Keychain属性・鍵消失・失効・再有効化・削除・バックアップ除外の全チェックを実行した。登録画面の同意と音声保存の初期オフ、最大3件・最後の音声のみ保持の説明も確認。実際にマイクで録音し、登録・再登録・中止・削除を通すE2Eは未検証。
- 登録中止はキャンセルを要求し、モデル処理の区切りで反映する。Core MLの推論自体が即時に停止することは保証しない。キャンセル確認後は新プロフィールを保存しない。
- 新たなAPI呼び出しやモデル導入はない。2〜3件登録では既存モデルの解析回数と一時音声容量が増える。実機の時間・ピークメモリ・電池は未測定。実音声・日本語会話・iPhone実機の確認と自動本人確定は引き続き未完了。

変更: `App/MemoraModel+VoiceProfile.swift`、`App/VoiceEnrollmentService.swift`、`App/VoiceProfileView.swift`、`App/SpeakerProfile.swift`、`App/VoiceQualityMetadata.swift`、`App/SpeakerProfileStore.swift`、`App/SelfChecks.swift`、`tools/checks/SpeakerProcessingChecks.swift`、本書、`docs/IMPROVEMENT_BACKLOG.md`。

追加: `App/VoiceEnrollmentSample.swift`、`App/VoiceEnrollmentBuilder.swift`、`App/VoiceEnrollmentFailure.swift`、`App/SpeakerProfileStorage.swift`、`App/SpeakerProfileStorageChecks.swift`。

### 既存ファイルを更新
- `App/Meeting.swift`
- `App/MeetingDetailView.swift`
- `App/MeetingSummarizer.swift`
- `App/MeetingSummary.swift`
- `App/MeetingSummaryInput.swift`
- `App/MeetingTranscriptContent.swift`
- `App/MemoraModel+Meetings.swift`
- `App/MemoraModel+Persistence.swift`
- `App/MemoraModel+Processing.swift`
- `App/MemoraModel+Templates.swift`
- `App/MemoraModel+VoiceProfile.swift`
- `App/MemoraModel.swift`
- `App/OnDeviceSummarizer.swift`
- `App/OnboardingView.swift`
- `App/ProcessingService.swift`
- `App/SelfChecks.swift`
- `App/SettingsView.swift`
- `App/SpeakerEditSheet.swift`
- `App/SpeechTranscriptionSegments.swift`
- `App/SpeechTranscriptionUpdate.swift`
- `App/SummaryGenerationSheet.swift`
- `App/SummaryMarkdownBuilder.swift`
- `App/SummaryMarketTemplate.swift`
- `App/SummaryPrompt.swift`
- `App/SummaryResponseParser.swift`
- `App/SummaryTemplateCatalog.swift`
- `App/SummaryTemplateCategory.swift`
- `App/SummaryTemplateMarketplaceView.swift`
- `App/TranscriptSegment.swift`
- `App/TranscriptionService.swift`
- `App/VoiceEnrollmentService.swift`
- `App/VoiceProfileView.swift`
- `Project.json`
- `docs/IMPROVEMENT_BACKLOG.md`
- `docs/THIRD_PARTY.md`

### 追加ファイル
- `App/FluidSpeakerDiarizationService.swift`
- `App/MemoraModel+Personalization.swift`
- `App/MemoraModel+Speakers.swift`
- `App/Occupation.swift`
- `App/OccupationCatalog.swift`
- `App/OccupationCategory.swift`
- `App/OccupationSelectionView.swift`
- `App/OccupationSummaryTemplates.swift`
- `App/Resources/Community1-LICENSE.txt`
- `App/Resources/Community1-NOTICE.txt`
- `App/Resources/FluidAudio-JapaneseG2P-LICENSE.md`
- `App/Resources/FluidAudio-KokoroAneSpanishFrenchG2P-LICENSE.md`
- `App/Resources/FluidAudio-LICENSE.txt`
- `App/Resources/FluidAudio-Nemo-LICENSE.txt`
- `App/Resources/FluidAudio-fastcluster-LICENSE.txt`
- `App/Resources/FluidAudio-vbx-LICENSE.txt`
- `App/Resources/NemoTextProcessing-NOTICE.txt`
- `App/Resources/NemoTextProcessing-THIRD-PARTY.txt`
- `App/Resources/OccupationCatalog.json`
- `App/Resources/SpeakerModelManifest.json`
- `App/SpeakerAnalysisResult.swift`
- `App/SpeakerDiarizationService.swift`
- `App/SpeakerEmbeddingMath.swift`
- `App/SpeakerIdentificationService.swift`
- `App/SpeakerIdentificationSettingsView.swift`
- `App/SpeakerIdentificationStatus.swift`
- `App/SpeakerInterval.swift`
- `App/SpeakerModelAssets.swift`
- `App/SpeakerModelProbe.swift`
- `App/SpeakerProcessingFailure.swift`
- `App/SpeakerProfile.swift`
- `App/SpeakerProfileReference.swift`
- `App/SpeakerProfileStore.swift`
- `App/SpeakerTranscriptAligner.swift`
- `App/SummaryHistoryView.swift`
- `App/SummaryLength.swift`
- `App/SummaryPreferences.swift`
- `App/SummarySection.swift`
- `App/SummarySectionIndex.swift`
- `App/SummarySensitivity.swift`
- `App/SummaryStyleSettingsView.swift`
- `App/SummaryTemplateSelector.swift`
- `App/SummaryUseCase.swift`
- `App/TemplateSectionDigest.swift`
- `App/TemplateSectionItems.swift`
- `App/TemplateSummary.swift`
- `App/UserOccupationProfile.swift`
- `App/VoiceQualityMetadata.swift`
- `App/VoiceEnrollmentProgress.swift`
- `App/VoiceSampleAnalyzer.swift`
- `docs/PERSONALIZATION_IMPLEMENTATION.md`
- `tools/checks/PersonalizationChecks.swift`
- `tools/checks/SpeakerProcessingChecks.swift`
- `tools/checks/SummaryLayoutChecks.swift`
- `tools/checks/SummaryPersonalizationChecks.swift`
