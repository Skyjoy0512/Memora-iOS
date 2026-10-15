# 公開Webページの本文取得（2026-10-15）

ソース詳細の「Web本文を取得」または「本文を更新」で取得する。URLの保存・詳細の
再表示・アプリ復帰だけではアクセスしない。取得した文字は既存のProjectSourceTextを
JSONファイルへ保存し、SQLiteには参照名とmetadataを保存する。元URL、タイトル、
取得日時、最終URLを保持する。privacy、索引・引用、projectの範囲は既存経路を使う。
外部AIへの送信許可を取得操作から付与することはない。

## 接続の境界

- HTTPS/443のみ。認証情報付きURL、IPリテラル、local/internal等を拒否。
- 既存MCPの公開アドレス判定・キャンセル可能なDNS待ちを共用する。DNSの全結果が
  公開IPであることを検証し、そのうちの**数値IP**へNetwork.frameworkで接続する。
  接続時にホスト名を再解決しないため、事前DNS検査だけのTOCTOUを避ける。
- TLS 1.2以上。SNIと証明書のSSL policyは元のホスト名。SecTrustEvaluateWithErrorで検証し、
  証明書用AIA/OCSP等の未検証URL取得はSecTrustSetNetworkFetchAllowed(false)で禁止。
  自己署名や名前不一致を許可する迂回経路・任意のtrust anchorは追加しない。
- redirectは自動追従せず、各hopでURLとDNSを再検証。最大3転送・4リクエスト。
  Cookie、認証情報、Referer、アプリの記録を送らない。接続を再利用せず、再試行しない。
- 接続/応答15秒、全体30秒。キャンセル・画面離脱・workspace変更・復元・削除で停止。
  後から返った結果は操作IDと現在のURL/所属/本文参照を照合し、不一致なら保存しない。
- アドレス判定は保守的。IPv4の特別用途帯、IPv6の2001::/23、2001:db8::/32、
  2002::/16、3fff::/20、ULA/link-local/translation等を拒否する。
  このうち一部の世界到達可能な特殊用途・NAT64環境も非対応になる。

URLSessionの通常のホスト名接続は、検証後のDNS再解決を固定できないため使わない。
代わりに小さなHTTP/1.1 readerを使用する。これはフル機能のブラウザーではない。
プロキシ必須のネットワークや、一部のIPv6環境では接続できない場合がある。

## 応答と文字の制限

- HTTPヘッダー32KiB/200行、本文2MiB、wire合計2MiB+64KiB。Content-Lengthとchunkedを
  明示的に検査し、二重length、length/transfer併記、不正chunk、途中切断、過大応答を拒否。
- text/html、application/xhtml+xml、text/plainのUTF-8/ASCIIのみ。圧縮はidentityのみ。
  gzip等、HTTP trailers、1xx early hints、他の文字コードには対応せず失敗を表示する。
- HTMLは文字として走査し、script/style/template/frame等と通常のnavigation/hidden要素を
  除外する。article→main→bodyの優先で文字を選ぶ。WebKit/HTMLのNSAttributedString
  importerを使わず、JavaScript、画像、CSS、外部entity、子リソースを実行・取得しない。
- XML/DOMやブラウザーの完全な再現ではない。HTMLは2MiB、30,000タグ、深さ128、
  tag 8KiBまで。出力80,000文字/UTF-8 256KiB/2,000行。結合文字を含んでも本文JSONは
  既存TextReaderの2MiB以内に収まる。元HTMLは保存しない。
- 画像/動画/動的表示等は未解析のため「一部をAI参照可」とする。本文ゼロ、認証が必要、
  unsupported、timeout、HTTP errorを成功と表示しない。失敗した更新は以前の本文と
  取得日時を保ち、失敗理由を表示する。未完了操作を保存・自動再送しない。

## 検証と残る範囲

`WebSourceChecks`はdefaultでネットワークを使わない。固定endpoint、混在DNS、private
redirect、request headers、分割HTTP/chunked、上限、非実行HTML、entities、Unicode、
処理中キャンセル、redirect loop、HTTP拒否を実装へfixtureで渡す。
一時的なローカル証明書を使い、実際の検証関数で未信頼証明書とホスト名不一致を
拒否し、テスト内でのみanchorを指定した正しいホスト名を受理することを確認する。
OS/keychainへ証明書をインストールせず、秘密鍵は一時ディレクトリとともに削除する。
`--live`は手動の公開ページ1件の確認専用で、定期実行・監視用ではない。
実行結果とSimulatorの保存・再表示は[品質改善記録](QUALITY_IMPROVEMENT.md)に記載する。

実サイト全般、ログイン、証明書欠落・悪性サーバーの実ネットワーク網羅、各ネットワーク、
実機、実BYOKとの統合は未検証。一般Web取得をagent toolへ自動公開する変更は含めない。
MCPのホスト名接続自体をIP固定に置き換える変更も行っていない。
App Group・bundle ID・バックアップ方式・有料契約/サービスの追加はない。

確認した一次資料:
[Apple TLS server name](https://developer.apple.com/documentation/security/sec_protocol_options_set_tls_server_name(_:_:))、
[SSL hostname policy](https://developer.apple.com/documentation/security/secpolicycreatessl(_:_:))、
[IANA IPv6 special-purpose](https://www.iana.org/assignments/iana-ipv6-special-registry/)。
