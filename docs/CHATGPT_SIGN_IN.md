# ChatGPT サインアップ / サインイン

Memora に「ChatGPTで続ける」を追加する。OpenAI の Sign in with ChatGPT
(open-source flow) を使い、ChatGPT のアカウントでサインインできるようにする。

## 前提

- 対象は open-source flow (`dynamic_agent_client` による動的登録)。
  partner の client ID は要用らない。client secret も API key も要らない。
- Identity (openid profile email) と plan usage
  (offline_access resource.invoke chatgpt.tokens.use.direct) の両方の scope を
  要求し、返ってきた scope でどちらが許可されたかを判断する。
- 计划和 (plan usage) は ChatGPT Plus / Pro の eligible ユーザーだけ。
  許可されなければ、その旨だけ表示する。会話へのアクセスは付かない。

## 参照

- 認可: `https://auth.openai.com/api/accounts/authorize`
- トークン: `https://auth.openai.com/api/accounts/oauth/token`
- 失効: `https://auth.openai.com/api/accounts/oauth/revoke`
- JWKS: `https://auth.openai.com/.well-known/jwks.json`
- -discovery: `https://auth.openai.com/.well-known/openid-configuration`
- resource: `https://api.openai.com/v1`

## フロー

1. この端末の host ID (`urn:uuid:...`) を作る。Keychain に保存し、起動をまたいでも
   同じ値を使う。
2. `state` / `nonce` / PKCE verifier を毎回新しく作り、
   `http://127.0.0.1:<port>/auth/callback` の loopback listener を先に立てる。
3. 認可 URL を開く:
   - 新規登録: `client_id=dynamic_agent_client`, `agent_name_hint=Memora`,
     `ext_agent_host_id=<host id>`
   - 登録済み: 保存済みの issued client ID (`oaiapp_...`)、`id_token_hint`,
     `login_hint`
4. callback 回来的ら `state` を照合し、`client_id` を受け取る。
   新規登録では発行された client ID を保存する (`dynamic_agent_client` は保存しない)。
5. トークン交換 (form encoded):
   `grant_type=authorization_code`, `client_id`, `code`, `code_verifier`,
   `redirect_uri`, `resource`
6. ID token を検証する: JWKS の署名を `iss` `aud` `exp` `nonce` と照合し、
   `sub` を本人 ID として保存する。
7. access token / refresh token / scope / 有効期限を Keychain に保存する。

## 保存するもの

- Keychain: host ID, issued client ID, ID token, access token, refresh token,
  検証済みの sub / email / name, scope, 有効期限
- UserDefaults: なし (認証情報は全部 Keychain)

## loopback callback の判断 (2026-11-24)

`ASWebAuthenticationSession` は `http://127.0.0.1` の callback を受け取れない。
callbackURLScheme は scheme を要求し、`https` は iOS 17.4 以降の
`Callback.https(host:path:)` (Universal Link) しか受け付けない。

OpenAI の open-source flow は `http://127.0.0.1:<port>/auth/callback` を
要求するため、**選択肢は (a) アプリ内の loopback listener + Safari**、
(b) partner flow 拿到登録済みの HTTPS redirect URI の2つ。

**採用: (a) を採用する。**

- 理由: open-source flow は partner 登録不要で、client secret や API key を
  一切持たない。失効時にポートを取り直すだけで再登録できる。
- 実装: `ChatGPTLoopbackCallbackServer` が `NWListener` を `127.0.0.1` の
  ephemeral port にだけ bind し、`/auth/callback` のみを受ける。`Host` ヘッダ
  と `state` を照合し、別 host や別 state の要求は 404 / 400 で拒否し、待ちを
  消費しない。ブラウザは Safari (`UIApplication.shared.open`) を使う。
- 接受しないもの: 別の interface への bind、`http` 以外の loopback 宛先の
  転送、`state` 検証の省略、コードを HTML に出すこと。
- 残存リスク: Safari は `http://127.0.0.1` への遷移を許可する。哪天、配給の
   accredited app だけ partner client ID を持てる様に restrictions がかかった
  ら、(a) は使えない。届时は partner client ID と Universal Link に移る。
  その場合の切替点は `ChatGPTOAuthTransaction.makeAuthorizationRequest` と
  `ChatGPTLoopbackCallbackServer` の2つだけ。

## 実装

- `App/ChatGPTHostIdentity.swift` — 端末の host ID。
- `App/ChatGPTOAuthEncoding.swift` — 乱数、PKCE challenge、form encoding。
- `App/ChatGPTOAuthTransaction.swift` — 認可要求、コード交換、更新、失効。
- `App/ChatGPTTokenResponse.swift` — トークン応答の検証。
- `App/ChatGPTIDTokenVerifier.swift` — JWKS での ID token 検証。
- `App/ChatGPTCredentialStore.swift` — Keychain への保存。
- `App/ChatGPTLoopbackCallbackServer.swift` — loopback 受信。
- `App/ChatGPTSignInCoordinator.swift` — フロー全体。

## 検証

- 鍵サーバーが落ちたとき `.verificationUnavailable`、鍵がないとき
  `.invalidToken` になること。
- 検証済みの ID token _none_ のときだけ保存すること。
- 別のアカウントでサインインすると、既存の接続を上書きしないこと。
