# 通信・保存の追加修正（2026-10-25）

実装/fixture検証済みの範囲を記す。実際のBYOK DeepSeek約50秒事象の原因は引き続き未確定。
実プロバイダー、OAuthアカウント、外部MCPサービスへの通信・有料API・本番変更は行っていない。

## MCP/OAuthのDNS再解決

Before: `MCPBoundedHTTPTransport.send` と `MCPOAuthClient.request` はpublic DNSを検査した後、URLSessionへホスト名を渡していた。二度目の解決が同じIPである保証がなく、DNS rebindingのTOCTOUがコード上にあった。実サーバーを使った攻撃試験はしていない。

After (`ed2969d`): `MCPPinnedHTTP.post` が検査済みIPを保持する `WebSourceRequest` を構築し、既存 `PinnedHTTPSConnection` を共用する。Network.frameworkのsocketにはnumeric IPを渡し、TLS SNI/証明書の信頼検査には元のhostを渡す。TLS 1.2以上、ALPN HTTP/1.1、証明書の追加ネットワーク取得禁止を維持。URLSession、hostname fallback、redirect、cookie/cache、無条件再送は使用しない。

- POSTのHost/Content-Length/framingは呼び出し元から上書きできない。ヘッダー注入・重複重要ヘッダー・圧縮・サイズ超過を拒否。
- MCP要求64KiB/応答2MiB、OAuth要求32KiB/応答128KiB、交換期限30秒/呼び出し全体35秒の上限。これは要約経路の300/600秒を変更するものではない。
- Web取得の既定GET/MIME/2MiB/15秒は変更せず、MCP/OAuthだけJSON/SSE用のdecoder設定を渡す。
- JSONは完全受信後だけ配信。SSEは完結イベントのJSON-RPC型/IDを検証して配信し、対応する最終返信でHTTP EOFを待たず閉じる。HTTP chunkがまだ終わっていなくても完結したSSE返信を読める。累積snapshotの既読部分を重複配信しない。
- notificationとサーバー起点requestへのresponseは空の202/204を受理。ID付きclient requestの空ack、途中EOF、不正JSON/UTF-8/ID/応答型は失敗する。MCP SDKの型/schema検証と実行時の権限検証は引き続き必要。
- session IDは返信をSDKへyieldする前に同期的に公開。初期化の次の通知が古いsession状態を見る競合を防ぐ。途中の別IDへの差し替えを拒否。
- disconnect/呼び出し元cancelは進行中のrequestを失効し、接続を停止。遅延callbackはsessionや受信streamを復活させない。
- OAuthのrefresh dedup、identity/権限の束縛、Keychain compare-and-replaceを維持。新認証/切断/cancel後の古いrefreshを保存しない。

本番の承認・コスト・endpoint fingerprint・workspace/context検証は変更していない。接続認証を資料参照許可へ昇格させない。ブラウザー認証のサイト遷移はアプリのsocket pinning対象外。

互換性の残課題: HTTP/2専用、圧縮専用、オンライン取得を要する不足した中間証明書、複数IPの自動failoverには未対応。失敗時に制限を緩めない。現在のSDK 0.12.1/2025-11-25プロトコルを維持し、新しい2026仕様への移行と混同しない。[固定仕様のPOST/SSE/ack/session](https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/docs/specification/2025-11-25/basic/transports.mdx) を参照。Memora管理サービスとして接続先審査・認可・料金・監査を一元保証するには信頼されたバックエンドを推奨するが、未構築であり、本番安全性確認済みとはしない。

## 保存パスの誤拒否

Before: 最初の総合runnerが `ProjectSourceStorageChecks` の新規note保存で `ProjectSourceFiles.Failure.invalidFile`。Foundationが既存の `/private/var/...` を `/var/...` に正規化する一方、存在しない子URLには元の綴りを残すことをread-onlyで確認。比較prefixが一致しなかった。

After (`acef618`): `ProjectSourceFiles.resolve` は既存親を正規化してから新規子を構築する。`..`、slash、backslash、NUL、親の外へ向く子symlinkの拒否を保持する。SQLite文書形式、参照ファイル名、媒体内容は変更しない。既存のroot自体がsymlinkである場合のFileManager mkdir対応まで拡張したものではない。

同じprivate/var環境の本番保存/24競合/SQLite rollback/reopen、取り込み32競合、既存Web復旧28競合、symlink親の新規leaf解決/逸脱拒否を検査。iOS実機のファイル保護・空き容量・Sandbox挙動は未検証。

## 長い診断の終端保持

Before: 先頭256イベントだけを画面用に保持し、それ以降の保存失敗や終了理由がOSLogにしか残らなかった。

After (`6a167fb`): 開始1件+末尾255件（受信中のlastTokenは追加1件）と省略件数。608イベントのfixtureでも最後のtoken/応答完了/保存失敗/終了理由を保持。モデル文字列のハッシュ化、本文/キー/任意エラー非記録、直近12ジョブの上限は維持。OSLogへの記録は継続。UI構成やGlassは変更していない。

## 検証と失敗履歴

`bash tools/checks/run-mcp-pinned-http-checks.sh` はSwift 6モードで本番HTTP/parser/MCP/OAuth actorを検査する。DNS/転送は注入fixture、SDK protocol/loggerとKeychainだけホスト代替。実SDKのconformanceは別のBitrigビルドで検査。外部通信なし。

全6ホストsuiteの追加実行はPass:
`/Volumes/WorkspaceSSD/Development/Agents/Codex/tmp/memora-quality/memora-quality-ns8tghh9/summary.json`
コピー [host-summary-mcp-followup.json](host-summary-mcp-followup.json)。その後の診断保持の最終追加は `run-summary-reliability-checks.sh` を個別再実行してPass（仮想30/60/120/180秒、初回60秒、2,178,128byteのDeepSeek推論fixtureを含む）。実時計/実プロバイダーの試験を今回再実行したとはしない。

- 初回全体実行 `memora-quality-9lhf07zq` は上記保存不具合でfatal error。調査のためrunnerを中断し、summaryは`interrupted`のまま保持（Passとしない）。修正後の同じprivate/var保存検査はPass、全体はWorkspaceSSDの専用scratchで再実行。
- 新MCP fixtureの初回compileはGmailError依存漏れ、次はthrowing autoclosureとenum factoryの扱いを誤りFail。runner依存とテスト記述を直し、検証条件を削らず再実行してPass。
- 新しいsymlink-parent fixtureは、root symlinkそのものにmkdirする準備処理で二度Fail。検証対象の`resolve`が返すcanonical URLへ書き込む正しい準備に直し、新規leafの保存と外向きsymlink拒否を厳密assertしてPass。既存のテストassertion削除やskipはしていない。
- MCP実サーバー/OAuthブラウザー・実Keychain/実機/TLS接続の運用E2EはNot Run。旧Web取得suiteの証明書信頼/hostname不一致検査と既存GET回帰はPassだが、実サービス互換性の代用とはしない。
- この追加作業はUI/デザインを変更せず、previewのビルド/起動を更新。新たなUI E2E/Light/Dark撮影は実施していない。以前のUI検証は [E](E_UI_UX.md) の範囲に限る。

ビルドの最終結果とGitHub CIは [C](C_TESTS.md)、[CI](CI.md) に記す。課金済みかもしれない操作の自動再送、権限緩和、Bundle ID/App Groups変更、実ユーザーデータの削除・復元は行っていない。
