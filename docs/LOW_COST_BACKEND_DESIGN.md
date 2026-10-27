# 認証・課金・低固定費バックエンドの接続設計

2026-10-27。設計のみ。アカウント作成、クラウドdeploy、課金契約、API実行は行わない。
現在の匿名ローカル利用、BYOK、未接続表示を継続する。

## 境界と所有権

個人データの正本はSQLiteと音声/写真ファイル。ログインしても勝手にアップロードしない。
将来のAuthBackendは未接続/認証中/認証済み/更新失敗を明確に区別し、サービス接続に成功した
UIDだけをアカウントとして扱う。現在のMemoraAccountや選択プランを認証/購入の証明にしない。
Apple/GoogleのOIDCとメールのcredentialをFirebase AuthenticationのUIDへ束ねる。
Appleはnonceとstateを一度だけ検証し、GoogleのOAuthはPKCE/state/redirect一致を必須にする。
メールは検証済みアドレスと未検証を分け、password/tokenをログやUserDefaultsへ保存しない。

匿名からの移行は「ローカルを継続」「明示した対象を同期」の選択を残す。移行manifest、
record UUID、所有UID、内容hash、媒体hashを対応させ、サーバー受領前にローカルを削除しない。
同名アカウント/別UIDを自動mergeしない。共有workspaceと個人データは別namespace/権限で扱う。
TokenはKeychain、更新は同一セッションで重複を防ぐ。ログアウトでsession generationを更新し、
古い通信・承認・同期書込を拒否する。ログアウトはローカルデータ削除を兼ねない。
アカウント削除は再認証後、クラウド削除の進捗を追跡し、ローカル保持の選択を明示する。

## 課金

第一候補はStoreKit 2。署名検証済みTransactionからだけ権限を計算し、
currentEntitlementsとupdatesを照合する。pending/cancelled/unverifiedは権限を増やさない。
返金・失効・更新・猶予期間を別に扱う。復元は利用者操作でApp Storeとの同期を要求し、
成功する前に復元済みと表示しない。会社ライセンスのEd25519検証経路は分離して保持する。

RevenueCatはクロスプラットフォーム権限と運用支援の利点があるが、外部データ連携と
従量コストが増える。今回導入しない。公式料金は2026-10-27確認時点で月間追跡売上
$2,500まで無料、その後1%。固定費ゼロと将来費用ゼロは同義ではない。
[公式料金](https://www.revenuecat.com/pricing)

StoreKitの権限確認は
[Apple currentEntitlements](https://developer.apple.com/documentation/storekit/transaction/currententitlements)
を正とする。実装前にSDKの利用可能なAPIをApple documentationで再確認する。

## 原価とクレジット台帳

年間売上を12で割ったネット受取額（手数料/税/為替/返金reserve控除）を、
毎月最大利用時のAI入力/出力/再試行/保存費と比較する。年額割引を売上計算へ必ず反映する。
API価格はサーバー側のversion付き単価表、為替と予算は保守的な設定値とし、UI価格を
原価承認の根拠にしない。docs/PRICING.mdの既存条件を満たせなければ販売を解禁しない。

サーバー台帳はaccount+period+request UUIDを一意にし、reserve→settle/releaseを原子的に行う。
開始前に入力/最大出力の上限費用を予約し、タイムアウトも同一request UUIDで照会する。
不明な結果への自動再課金を禁止する。負残高、同時要求による二重消費、再送による二重付与、
返金後の権限継続を拒否する。台帳と上限/監視/停止スイッチが整うまで「無制限」の販売なし。
アプリのMemoraCreditMeterは残高の写しであり、付与や消費の正本にならない。

## Firebase / Cloudflare

Firebase AuthenticationのSparkを認証候補とし、SMS/有料機能を既定で有効にしない。
SparkとBlazeの差と各機能の制限は
[Firebase公式](https://firebase.google.com/docs/projects/billing/firebase-pricing-plans)
を接続前に再確認する。無料枠の保証として扱わない。

将来、短いHTTPS要求に応答するWorker、台帳/索引を置くD1、媒体を置くR2を候補とする。
WorkerはFirebaseの署名済みtokenを検証し、UID/workspace/record ACLを要求ごとに判定する。
D1の条件付き更新/transactionで台帳を守り、R2には短命署名URL、content hash、サイズ、
媒体型、取得許可の検査を適用する。公開bucketに個人記録を置かない。

Workers Freeには日次要求上限があり、超過時はサーバー機能を止め、ローカル利用へ戻す。
無料枠を超えたら自動でPaidへ移行させない。現時点の制限は
[Workers公式](https://developers.cloudflare.com/workers/platform/limits/)と
[D1公式](https://developers.cloudflare.com/d1/reference/faq/)を正とする。
R2を含むサービスの有効化や請求先の登録には別途明示承認が必要。

24時間常駐Agent、Paid Workers、Durable Objects上の常駐、VPS、常時containerは作らない。
ResidentAgentは引き続きiOSの裁量実行で、厳密な定刻実行を保証しない。

## 接続の解禁条件

認証/匿名移行のrollback、token更新/失効、所有権、アカウント削除、権限取消、
StoreKit sandboxの購入/復元/返金、台帳の同時実行/再送、原価の最悪条件、
同期の競合/媒体破損を実検証してから機能を開く。設計書の存在を接続完了と扱わない。
