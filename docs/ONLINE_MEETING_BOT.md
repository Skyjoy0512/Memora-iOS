# オンライン会議の録音取得

調査日 2026-11-25。対象は Google Meet と Microsoft Teams。公開アプリの Bot 参加可否と、主催者が録音したファイルの取り込み可否はそれぞれ評価する。

## Memora の現状

- `FeatureFlags.isOnlineMeetingCaptureEnabled` は無効。保持している画面は、スピーカーで再生された音を端末マイクで収録する案内。作成メニューとカレンダーの録音方法はフラグで制御され、会議に参加するサービスはない。
- EventKit の `CalendarService.hasMeetingLink` は会議方法表示用の文字列判定。Bot への送信先の検証には使えない。`CaptureIntent.meeting` も会議マーク付き参照リンクの保存経路。
- 取得済み音声は `MemoraModel+CaptureCoordinator` の `.audio` 経路から現行の `importAudio`・文字起こし・要約に渡せる。音声インポートは現在、Bot のジョブ ID を重複防止用に受け継がないため、取得の再試行と端末保存を接続する前に安定した取り込み識別子が必要。
- [CalendarEventSheet](../App/CalendarEventSheet.swift) の通常録音とは別に、ライブラリの [UpcomingEventsRow](../App/UpcomingEventsRow.swift) は録音方法シートの閉じ処理を固定待ち時間で推定していた。閉じ完了通知から操作を一度だけ実行し、保存先の状態を再確認するよう変更した。端末マイク録音と前回記録への遷移が対象。

## 参加方式と権限

| 選択肢 | 確認できたこと | 次の条件 |
| --- | --- | --- |
| Google Meet の参加 API | リアルタイムの Meet Media API は 2026-10-28 に終了が発表され、2027-01-15 に停止予定。Meet REST API は会議管理と生成済み成果物を提供する。 | 主催者が Meet 内で生成した録音の取り込みを先行候補にする。ユーザー認可、録音可能な契約と管理者設定、Drive へのアクセス権、必要な OAuth 検証とデータ保持の条件を確認する。 [Google リリースノート](https://developers.google.com/workspace/meet/release-notes) · [Meet の認可](https://developers.google.com/workspace/meet/api/guides/authenticate-authorize) · [録音成果物](https://developers.google.com/workspace/meet/api/guides/artifacts) · [録音の条件](https://support.google.com/meet/answer/9308681?hl=en) · [Google Workspace データポリシー](https://developers.google.com/workspace/workspace-api-user-data-developer-policy) |
| Microsoft Teams の参加 API | Graph のアプリホスト型メディア Bot の本番環境は Azure の Windows Server と .NET SDK を要求する。録音前の `updateRecordingStatus` の成功、Teams のポリシーベース録音が条件。会議参加の権限・管理者同意も必要。 | 認定およびテナント管理者の経路を確認する。既存 Teams 録音の取得は Graph の別経路で、委任権限でのダウンロード主体は原則主催者。アプリ権限は組織側の認可を別途確認する。 [メディア Bot の要件](https://learn.microsoft.com/en-us/microsoftteams/platform/bots/calls-and-meetings/requirements-considerations-application-hosted-media-bots) · [録音ステータス](https://learn.microsoft.com/en-us/graph/api/call-updaterecordingstatus?view=graph-rest-1.0) · [Teams コンプライアンス録音](https://learn.microsoft.com/en-us/microsoftteams/teams-recording-compliance) · [録音の取得権限](https://learn.microsoft.com/en-us/graph/api/callrecording-get?view=graph-rest-1.0) |
| Vexa Lite の自己ホスト | upstream の安定版は `v0.12.28`（`f1a62fbbdfd2c98cb162582d82c31fe8102acc89`、Apache-2.0）。Playwright が Meet / Teams に参加する仕組み。PostgreSQL と S3 互換ストレージを併用し、Bot は Lite 内の子プロセスとして動く。API には音声取得のみの指定と録音データの取得・削除がある。 | 閉域の評価候補。ブラウザー参加・録音を許可した検証テナントが必要。録音専用の境界とプロセス分離を検証し、安定版の共有ディスプレイ・音声環境は複数利用者で使わない。 [リリース](https://github.com/Vexa-ai/vexa/releases/tag/v0.12.28) · [ライセンス](https://github.com/Vexa-ai/vexa/blob/v0.12.28/LICENSE) · [Lite 構成](https://github.com/Vexa-ai/vexa/blob/v0.12.28/deploy/lite/README.md) · [会議 API](https://github.com/Vexa-ai/vexa/blob/v0.12.28/docs/docs/api/meetings.mdx) |
| OpenMinutes の自己ホスト | `v0.4.0` の公開リポジトリは AGPL-3.0。Meet / Teams のブラウザー参加、音声取得と文字起こしの処理を持つ。 | 比較候補。ネットワーク経由提供時のライセンス条件、音声取得だけで運用できるか、対応テナントでの録音を確認する。 [リポジトリ](https://github.com/dennisklappe/openminutes/tree/v0.4.0) · [リリース](https://github.com/dennisklappe/openminutes/releases/tag/v0.4.0) |
| Attendee の自己ホスト | Meet / Teams 対応を掲げる。リポジトリの Elastic License 2.0 には、機能を第三者へホスト型サービスとして提供する場合の制限がある。 | Memora が運営する共有サービスの候補にする前に、ライセンス上の可否を確認する。 [対応会議](https://attendee.dev/) · [ライセンス](https://github.com/attendee-labs/attendee/blob/main/LICENSE) |
| Chrome 拡張でローカル取得 | デスクトップ Chrome はユーザー操作を起点に、対象タブの音声を取得できる。 | 端末上で利用者が録音を開始し、書き出した音声を取り込む経路の候補。マイクの合成、録音通知、権限、同意、対象プラットフォーム規約を別途確認する。 [Chrome の録音 API](https://developer.chrome.com/docs/extensions/how-to/web-platform/screen-capture) |

Docker Hub の公開マニフェストを照合した。Lite `v0.12.28` は Linux amd64 / arm64 を公開。arm64 レイヤーの合計は公開メタデータ上で約 1.96 GB。独立配布の `vexa-bot:v0.12.28` は照合時点で amd64 のみ。アーキテクチャの公開と実際に入室・録音・削除できることは検証段階が異なる。main の `6b26f7b921756d6db128d42cd70b4b7046381407` には Bot ごとの UID・音声・画面分離が記載されている。評価するビルドはダイジェストで固定し、Chromium のサンドボックスを含めて検証する。[Lite イメージ](https://hub.docker.com/v2/repositories/vexaai/vexa-lite/tags/v0.12.28) · [Bot イメージ](https://hub.docker.com/v2/repositories/vexaai/vexa-bot/tags/v0.12.28) · [main の分離設計](https://github.com/Vexa-ai/vexa/blob/6b26f7b921756d6db128d42cd70b4b7046381407/deploy/lite/README.md)

## 実装時の境界

1. 認証済みのユーザーが会議を指定する。サーバーで URL と対象プロバイダーを確定し、正規 HTTPS ホスト・参加用パスを判定する。任意 URL を取得させず、参加先と音声取得先を別々に制限する。招待 URL を解析ログに出さない。
2. ユーザーが会議・録音範囲・保存先を確認し、主催者と参加者への通知・同意を成立させる。通知や入室許可の状態が取得できなければ録音を開始しない。公式の通知を補完する Bot 名やチャットの通知は、対応テナントで確認する。
3. アプリは共通の `MeetingBotProvider` を通じて参加要求・状態取得・停止・音声取得を行う。サーバーが要求 ID を冪等に処理し、所有者・ワークスペース・参加先を各操作で照合する。入室待ち、拒否、切断、録音、音声確定を区別し、入室や失敗後の自動再参加はユーザーの指示と紐付ける。
4. Vexa Adapter の閉域評価では `transcribe_enabled=false` と `recording_enabled=true` を明示する。文字起こし設定を入れず、追加の Agent 機能を公開しない。サイズ・音声形式・完全性を検証し、許可されたダウンロードをアプリの一時保存領域にストリーミングする。API キーはサーバー内に置く。
5. 端末の `LocalImportContext` を開始時から取り込み時まで再確認する。取得の再試行で記録を増やさず、保存成功時に一時ファイルを削除する。バックエンドの音声は受領確認後に削除し、未取得分も期限で削除する。通知、TTL、削除ジョブ、上限到達時の拒否を障害系テストに含める。
6. 最大接続数、入室待機時間、会議時間、ユーザー別・全体の月間上限をサーバーで予約し、制限超過を契約額より先に止める。業務テナントごとの権限と、利用者間で音声が混ざらないことを実測する。

## 運用費の試算

| 運用先 | 公開条件 | 用途の判断 |
| --- | --- | --- |
| OCI Always Free | A1 は 1,500 OCPU 時間と 9,000 GB 時間/月、Always Free tenancy の目安は 2 OCPU / 12 GB。リージョンの在庫制約と低利用時の回収がある。 | ARM64 の閉域・単一利用者の計測候補。 [Oracle の現行条件](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm) |
| Google Cloud 無料枠 | 適格な米国リージョンの e2-micro 1 台相当、標準ディスク 30 GB 月、地域条件付き転送 1 GB/月。 | 制御用の候補。ブラウザー・DB・ストレージを含む同時稼働は未計測。64 kbps 音声だけで 1 GB は約 34.7 時間分。 [無料枠の条件](https://docs.cloud.google.com/free/docs/free-cloud-features) |
| Hetzner ARM VPS | 2026-06-15 適用、ドイツ・フィンランドの税別・IPv4 別の月上限は CAX11 €5.99、CAX21 €10.49。 | CPU を共有するため参加から音声確定までの負荷計測が必要。 [価格表](https://docs.hetzner.com/general/infrastructure-and-availability/price-adjustment/) · [製品構成](https://www.hetzner.com/cloud/cost-optimized/) |
| 自己ホスト | 既存ホストを所有者が管理。サーバー、回線、障害復旧は運用者負担。 | 単一組織を先行候補にする。利用者間分離と更新手順を確認する。 |
| Vexa ホスト型 | 公表の Capture は USD 0.30/Bot 時間、文字起こし加算は USD 0.20/時。個別の料金・STT 有無・削除条件は契約前に確認が必要。 | 300 録音時間なら Capture だけで USD 90/月の比較値。プライバシー文書には外部 STT への送信が記載されており、取得のみの設定と削除条件を実証するまで運用候補に含めない。 [料金](https://vexa.ai/pricing) · [プライバシー通知](https://vexa.ai/legal/privacy) · [データ処理条件](https://vexa.ai/legal/dpa) |

以下は設計時の仮定で、実測値ではない。音声の転送サイズを 64 kbps とすると 28.8 MB/時。16 kHz・16 bit・mono PCM なら 115.2 MB/時。月 300 収録時間では 64 kbps の音声を一度ずつ配送して 8.64 GB、均等収録・7 日保持なら常時約 2.02 GB。転送 10% 再試行で約 9.50 GB/月。会議プロトコル、失敗録音、コピー、DB、ログ、バックアップ分を加算する。

ホスト 1 台で最大 2 会議、ピークを見込んだ稼働率 25%、月 730 時間と仮定すると 365 Bot 時間/月が目安。CAX21 1 台・実利用 300 時間では VM のみ €0.035/収録時。月 1,000 時間なら時間だけで最低 3 台、VM のみ €31.47/月となる。同時会議のピークが 6 を超える場合はさらに台数が要る。録音が少ない月も VM は固定費になり、待機による Bot 時間、通信超過単価、事故対応、ストレージ、税、冗長化費が加わる。1 台当たり同時数は CPU・メモリ・録音欠損率の測定で決める。

## 検証状況

- リポジトリの経路、公式の認可要件、ライセンス、API と公開イメージのメタデータを確認した。現環境では Docker CLI、同意取得済みの検証会議、主催者・テナントの認可がなく、入室・録音・取り込みの PoC と同時実行計測は未実施。
- 公開前の判定は、許可されたテナントで一件の音声取得を確認し、ロビー拒否、強制退出、再試行、通知、保存後・期限後の削除まで行う。件数を増やす前に、同時 2 会議で音声の混在がなく、コスト上限が機能することを確認する。
- 既存アプリの録音機能を検証する場合は、カレンダーの録音方法シートを開き、閉じる操作で後続の画面が開かないこと、対面録音の選択から閉じ完了後に一度だけ録音画面へ進むこと、前回記録のリンクを開けることを確認する。
