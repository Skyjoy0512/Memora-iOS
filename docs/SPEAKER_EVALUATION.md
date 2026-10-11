# 本人識別の評価（自動確定は無効）

## 現在の状態
登録・録音解析は同一 Community-1 / 固定revisionの256次元embeddingを使用する。128次元PLDA空間は比較しない。FluidAudio v0.17.7の実公開API `ChunkEmbedding.startTimeSeconds/endTimeSeconds/embedding256` を確認して利用している。
公開ソース: https://github.com/FluidInference/FluidAudio/blob/v0.17.7/Sources/FluidAudio/Diarizer/Core/DiarizerTypes.swift

各chunkの有限値・次元を確認し、実話者区間の発話が1秒未満、または他話者と重なるchunkは集約から除外する。1秒は既存の匿名区間割り当てと同じ保守的な品質下限であり、本人判定精度を保証する基準ではない。適格chunkを平均・L2正規化する。騒音の自動定量評価は未実装。検出されない重なりや誤分離は残りうる。

## 同意のある実音声での収集
全参加者の録音・評価利用への同意を得る。評価音声・特徴量・個人名・スコアデータをGit管理下へ置かない。本人の登録時の同意だけを他人の評価同意として扱わない。

アプリ内の評価ハーネスは以下の実経路を使える（UIからの一般向けエクスポートは追加していない）：
1. `FluidSpeakerDiarizationService.shared.analyze(audioURL)` で解析。
2. 原音声を人が確認し、結果のS1/S2等に正解の匿名UUIDを割り当てる。本人の正解は登録済み `SpeakerProfile.id` と同じUUIDにする。
3. `SpeakerEvaluation.collect(profile:result:audioID:expectedSpeakers:device:environment:consentAt:quality:)` で実類似度を収集。本人判定・話者名の書き換えはしない。未検証品質は `.unreviewed`、雑音・重なり・短い発話は各除外状態、確認できた発話だけ `.approved`。
4. `SpeakerEvaluation.export(samples)` のJSONを、端末内の保護された評価用領域へ明示保存する。JSONにはスコア・匿名ID・環境・発話量・モデル情報・同意日時のみ。音声・embeddingは含めない。自動永続化・自動共有はしない。

## FAR/FRRレポート
リポジトリの外に実行ファイルとデータを置く。端末や環境を混ぜた集計だけでなく、環境/機種別にファイルを分けて確認する。

```sh
swiftc App/SpeakerEvaluationSample.swift App/SpeakerEvaluationReport.swift \
  App/SpeakerEvaluation.swift App/SpeakerEmbeddingQuality.swift \
  App/SpeakerIdentificationService.swift App/SpeakerEmbeddingMath.swift \
  App/SpeakerProfile.swift App/VoiceQualityMetadata.swift App/SpeakerAnalysisResult.swift \
  App/SpeakerInterval.swift App/SpeakerProcessingFailure.swift tools/speaker-evaluation.swift \
  -o /private/tmp/memora-speaker-evaluation
/private/tmp/memora-speaker-evaluation /private/path/samples.json 0.6,0.7,0.8
```

値は走査例で、推奨しきい値ではない。出力は各しきい値の混同行列、FAR（他人の誤受入/他人試行）、FRR（本人の誤拒否/本人試行）。片方の正解クラスがない場合その率はnull。未同意・不正値・異なるモデル空間の混在を拒否し、承認済み品質以外は除外数に計上する。データセットの正解・同意の真正性は人の確認が必要。

本人同士/本人と他人、複数性別・声質、室内/周囲の会話/美容室、短い/長い発話、内蔵/Bluetooth/Watch相当の音質を比較する。しきい値探索用と最終評価用の話者・音声を分け、他人の誤受入を重視しサンプル数と不確実性を報告する。

## 未完了
実音声の収集、iPhone実機での解析、FAR/FRRの実測、検証済み判定ポリシー、自動「自分」確定は未完了。単体テストの合成スコアは計算式の検証で、精度評価ではない。評価レポートを読み込んで自動確定を有効化する経路はない。
