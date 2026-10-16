# 人物IDとジャーナルの関連付け

2026-10-17。`c42ab2a`からの継続実装。既存SQLite、BYOK、個別の送信許可、タブ・FAB・下部コンポーザーを維持する。新しい依存、サーバー、API利用は追加していない。

## 動作と確度

手動のメモ・写真・イベントの作成/編集で「関連する人物」を選べる。ネイティブの一覧とToggleを使い、選んだ完全UUIDだけを`LifeLogEntry.personIDs`へ保存する。同名人物は既存`PersonSelectionOption`のメモ/ID表示で識別する。名前の入力やAI出力だけで人物IDを確定しない。

人物詳細では「関連付けたジャーナル」と「名前の言及のみ・本人未確認」を分け、どちらも元の記録を開ける。名前だけの候補は現在の人物一覧で名前が一意かつ2文字以上の場合だけ表示し、すでに別の人物IDを指定した記録は候補にしない。空白や全半角の違いは既存の名前正規化で扱う。関係の指定は本人の発言や会議参加を証明するものではない。会議由来のサマリー/タイムラインの確度は変更しない。

既存データには自動で人物IDを付けない。旧形式の`personIDs`省略/nullは空配列として読み込み、重複IDは正規化する。既存の写真ファイル参照、日時、本文を維持する。バックアップは既存のLifeLogEntry codecを通して関連IDも保存する。人物削除後も古いIDを残し、同名の別人へ自動では移さない。削除済みの関連は編集で保持/解除できる。

## 許可と失効

- 新しい人物指定では少なくとも「個人・顧客情報」に分類する。関連の追加/変更/解除と人物統合では外部送信許可を解除する。元会議が機密の場合はその分類を下げない。
- 人物を指定した記録のプライバシー設定では個人分類の下限を適用する。読み取りでも下限を再確認し、分類を満たさない保存値の送信許可は利用しない。
- 人物限定Ask AIは開始時に明示的なjournal IDを固定する。`read_person`、`search_records`、`read_record`は、その範囲と各記録の送信許可を別々に確認する。名前だけの言及は人物限定の範囲に含めない。
- Journal IDはmeeting ID/task IDと別の集合として保持する。同じUUIDの別種の記録へ権限を流用できない。project sourceの既存の拒否も維持する。
- 位置情報/自動検出記録は、人物の関連や保存された許可があっても外部AIへ渡さない。元会議が非公開または存在しない関連記録も拒否する。自動agentには追加の許可が必要。
- 関連解除・記録削除・人物統合/削除は既存の`personPolicyIsCurrent`で検出し、ツールと次のクラウド送信を停止する。内容編集/許可失効は既存のtyped referenceとfingerprintでも再確認する。新しい処理を自動再実行しない。
- 人物統合はpeople/tasks/meetings/journalを単一SQLite transactionで保存してからモデルへ反映する。途中失敗で一部の関連だけ移らない。作成/編集の保存失敗ではフォームを保持してエラーを表示する。

## 変更ファイル

|領域|App配下のファイル|
|---|---|
|保存/人物変更|`LifeLogEntry.swift`、`MemoraModel+Journal.swift`、`MemoraModel+JournalPeople.swift`、`MemoraModel+People.swift`、`MemoraModel+RecordPrivacy.swift`|
|人物限定取得|`AIPluginExecutionPolicy.swift`、`MemoraModel+PersonChat.swift`、`MemoraModel+PersonScope.swift`、`MemoraModel+PersonTools.swift`、`MemoraModel+AutomaticRecordTools.swift`|
|UI|`JournalPeopleFields.swift`、`LifeLogCreationSheet.swift`、`LifeLogEditSheet.swift`、`LifeLogEntryDetailView.swift`、`PersonMemory.swift`、`PersonDetailView.swift`、`PersonEditSheet.swift`|

## 自動検証

`bash tools/checks/run-person-journal-checks.sh`は本番のjournal codec/変更、人物集約/統合、人物限定取得、プライバシー設定をコンパイルして、隔離した実`LocalStore` SQLiteで検証する。`PersonFixtureModel.swift`にUI、通知、メディア、会議の形状とモデル保存口のfixtureをまとめ、既存の人物タスク検査でも本番のjournal codec/許可処理を使う。

- 同名人物、複数人指定、名前だけの旧メモ、旧形式の復元、ID重複排除。
- 不明な人物IDの拒否、本文編集によるfingerprint変更、分類下限と許可の失効。
- 人物限定のread/search、範囲外/非公開記録の拒否、別workspace/復元中の拒否。
- 同じUUIDのmeeting/journalを両方向に分離、位置情報/自動origin/非公開親/不明な親の拒否。
- 一括保存の最後のjournal書込をSQLite triggerで失敗させ、先行した人物・会議・タスクも巻き戻ること。
- 統合時の重複排除、関連解除、記録の削除復元、人物削除後の同名再登録、削除済みIDの保持、SQLite再読込。

実ユーザーの記録をテスト用に編集/削除したり、APIキー/有料API/外部認証を使ったりしない。ビルドと既存runnerの最終結果は[検証記録](ASK_AI_NEXT_VALIDATION.json)のfollowupsへ記録する。

Debug previewと指定のnext-generation/motion-loading/optimization各runnerは成功。シミュレーターでは未保存の作成フォームを使って人物選択→1人の表示→解除→指定なしの表示→キャンセルを確認した。ダークで通常/大きい文字のForm、ライトで大きい文字の人物一覧、AXの操作名/on・offを確認した。表示を元のダーク/標準文字サイズへ戻し、既存のコンポーザー下書きを維持した。記録の保存や既存本文の読取りによる回答検証は実施していない。同名選択・編集保存・削除済み人物のUI通し操作は未検証で、同名/保存/削除はhost fixtureでの確認。

## 残る範囲

- 実BYOKでの回答品質、端末上での通信中の許可変更、実機の性能/VoiceOver音声走査は未検証。
- 人物metadata自体の独立した送信許可/fingerprintは未実装。人物ツールを使った過去回答は永続的なcloud再利用について引き続き不完全と扱う。
- Ask AIの引用UIと生成資料/メールの保存済み出典は主にmeeting単位。journalのtyped referenceは実行中の許可確認に使うが、全成果物へtyped sourceリンクを追加する作業は別途必要。
- ゴミ箱内の旧人物IDを人物統合で書き換えない。復元後は削除済みIDとして残し、本人が選び直せる。元の本文を書き換えたり、名前だけの言及をまとめて確定したりしない。
