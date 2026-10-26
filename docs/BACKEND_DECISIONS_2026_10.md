# 認証・課金・低固定費バックエンド（設計のみ）

2026-10-27。サービス作成/契約/接続/deployは行わない。月額固定費0を今回の境界にする。
個人SQLite・録音・文字起こし・検索・資料生成・iOS Residentは端末内に残す。

## 判断

認証の第一候補はFirebase Authentication（Apple/Google、必要時メール）。代替はSupabase Auth。
FirebaseのAuthだけを利用し、Firestore/Analytics/Storageをまとめて追加しない。
課金はStoreKit2を第一候補にする。複雑なクロスプラットフォーム運用が必要になればRevenueCatを再評価。
server creditを提供するならいずれもserverでのtransaction/通知検証と原子的台帳が必要。

| 候補 | 公式公開の無料枠・費用/制約 | Memoraでの扱い |
| --- | --- | --- |
| Firebase Auth | Other Authenticationはno-cost、Identity Platformは50K MAU枠、SMSは送信別料金 | SMSを使わずAuthのみ候補。quota、メール送信、濫用対策、provider設定を接続前に確認。Cloud Billingを無断有効化しない |
| Supabase Free | 50K MAU、DB500MB、file1GB、egress5GB、非稼働1週間でpause、active2project | Auth代替。SMTP/メール到達・pause・RLS/運用を含めて比較。現行SQLiteを移す理由にしない |
| Workers Free | 100,000req/日、CPU10ms/invocation | 小さいAPI proxy/JWT/認可のPoC候補。圧縮PPTX/画像rendererの実行は10msに収まると仮定しない |
| D1 Free | read5M行/日、write100K行/日、total5GB | metadata/credit台帳候補。索引なしscanの原価、tenant複合key、unique idempotency keyを設計 |
| R2 Standard | 10GB-month、Class A1M/月、B10M/月の無料枠。超過storage$0.015/GB-month、A$4.50/M、B$0.36/M、egress無料 | 従量課金/決済情報が必要になる可能性がある。今回有効化せず、共有時だけ署名URL・quota・保持期限を設計 |
| StoreKit2 | SDKの追加サービス利用料なし。App Store手数料/契約/Developer Programは別 | iOSの取引/復元/失効を直接処理。local plan選択をtransaction/有効課金とみなさない |
| RevenueCat | 月間tracked revenue $2,500まで無料、超えるとtracked revenueの1%という公開条件 | App Store手数料とは別。匿名ID/link/権限の運用が軽くなる一方service依存/追加データ共有。今回は接続しない |

出典: [Firebase](https://firebase.google.com/pricing)、[Supabase](https://supabase.com/pricing)、
[Workers](https://developers.cloudflare.com/workers/platform/pricing/)、[D1](https://developers.cloudflare.com/d1/platform/pricing/)、
[R2](https://developers.cloudflare.com/r2/pricing/)、[RevenueCat](https://www.revenuecat.com/pricing)。
枠/価格は将来変わりうる。無料枠でも外部費用ゼロの保証ではない。
プラン原価と年額割引のリスクは[PRICING.md](PRICING.md)で別計算する。

## 認証とデータ所有権

- local利用にはuserIDを強制発行しない。ログイン後もprivate recordの自動uploadなし。
- Apple/Googleの本人確認とMemoraのworkspace認可を分離。clientのteamIDを信用せずserver membershipを確認。
- nonce/state/PKCE、正しいcallback、Keychainの端末ロック保護、token rotation/refresh失敗/失効を扱う。
  ID tokenは短命、secret/provider refresh tokenをUserDefaults/ログに置かない。
- serverはJWTのissuer/audience/alg/exp/JWKS rotationを検証。clientでdecodeしたclaimだけで認可しない。
- 匿名→本人linkは重複アカウント/既存所有者の確認が必要。メール一致だけで結合しない。
  Apple relayは本人確認に用い、公開プロフィールへ実メールを出さない。
- ログアウトはcloud token/permission/候補cache/進行requestを失効し、private local recordを勝手に削除しない。
  アカウント削除はrecent authentication、server job受付、token revoke、保持/削除期限、完了通知を用意。
  個人localとteam所有物の削除を分離し、offlineでcloud削除が完了したと表示しない。
- 複数端末はserverのuser/workspace/revisionが基準。UI上のwrite承認やcalendar grantは同期/復元しない。

## 課金・creditの境界

StoreKit2のverified transaction/current entitlements/updates/restoreを独立したbilling adapterへ。
pending/cancel/unknown/unverifiedを成功にしない。サブスク期限、grace period、billing retry、
refund/revoke、trial eligibilityを扱い、App Store Server Notifications V2/Server APIで照合する。
通知は署名・bundle/environment・重複ID・original transaction・期限を確認し、逆順にも対応。
server未接続ではcloud credit/席数をlocal選択で発行しない。

creditは(userID, workspaceID, requestID)で予約→実行→確定/取消。
出力・推論・cache miss・全tool・続行/retryを予約上限に含める。
処理は月跨ぎ・複数端末・重複通知に冪等。usage欠落や中断を無料と仮定せず、
上限予約を残して照合する。未知料金の外部readを自動jobへ許可しない。

## 同期/APIの最小契約（未実装）

| 値 | 責任 |
| --- | --- |
| userID / workspaceID | serverの本人/tenant。local personalをteamと混同しない |
| recordID / projectID / documentID / sourceID / agentID | 既存UUIDを維持、移行のために新IDへ置換しない |
| revision / updatedAt | serverの楽観lockと表示時刻を分離。端末clockだけで勝者を決めない |
| deletedAt / syncStatus | tombstoneとlocal pending/conflict/error、削除伝播/復元の明示確認 |
| idempotencyKey | user/tenant/operationに束縛。異なるpayload再利用は409 |
| permissions | 毎requestのrole・record privacy・source access。model出力はgrantにならない |

push/pullはcursorとrevisionで増分、mediaはchecksum/size/MIME/短命URLと原子的確定。
local保存成功とcloud確定は別status。復元はbackup互換、rollback、未送信変更を保持。
revisionを追加しただけでsync済みと表示しない。

ResidentのAgent定義/Trigger/Runtime/Tool registry/Permissions/Budget/State/Notification/
Memory/Historyは責任を分けるが、今回unused汎用frameworkは作らない。
既存BGTaskScheduler/復帰/会議後を維持。24時間保証のためのPaid Workers/DO/Agents SDK/
Trigger.dev/VPS/containerは、ユーザーの次回指示まで明確に保留する。

## 本番接続前に必要な未取得設定

Firebase project/client ID/Apple provider、URL scheme/entitlements、Apple/Google consent、
server endpoint/JWT audience、StoreKit product/subscription group/App Store Server key/通知URL、
D1/R2 bindingとquota/削除policy。秘密値はチャット・Git・スクリーンショットへ出さない。
これらの作成や課金契約を、設計書を作ったことから自動で承認済みと解釈しない。
