# MCP OAuth: supported subset

2026-10-13. This increment extends the existing MCP client and editor; it does not replace Ask AI, tools, approvals, providers, scopes or navigation.

## Setup

In the MCP server editor enable **ブラウザーでサインイン（OAuth）** and supply:

1. Existing public Client ID registered with the provider. No Client Secret is accepted.
2. HTTPS authorization and token endpoints on the **same host**, without query strings/credentials/fragments. Cross-host providers are unsupported in this first version.
3. Explicit minimal scopes, space-separated (at most 16). Empty/default scopes are deliberately unsupported.
4. Register **`memora://oauth/mcp`** as the exact redirect URI at the authorization service. The app already registers the `memora` URL scheme; no bundle ID or project configuration was changed.

Press サインイン explicitly. Browser authentication is ephemeral and uses ASWebAuthenticationSession. The official Swift SDK 0.12.1 provides PKCE S256 and callback/code validation; the app adds strict callback base/duplicate-parameter/state/error validation. Resource is the normalized MCP endpoint on both authorization and token requests (RFC 8707). Returned scopes may narrow, never expand, the approved scope set.

Successful token storage is labeled **認証情報あり**, not a verified tool connection. Press 接続を確認 separately; automatic read permissions still require explicit tool fingerprint review and declared-free usage. Existing Bearer mode remains available and retains backward-compatible configuration decoding.

## Storage and execution

- OAuth settings are preferences (`MCPServerConfig.oauth`, optional for legacy JSON). Tokens are a separate Keychain item `mcp.oauth.<server UUID>`. They are never stored in UserDefaults, records, backups, logs or the editor text fields.
- Credentials carry a SHA-256 identity derived from MCP resource, Client ID, authorization endpoint, token endpoint and exact normalized scopes. Changing identity clears old authentication and automatic tool permissions. Old OAuth tokens never fall back to the manual Bearer path. Connection generations prevent a late SDK initialization from caching credentials after disconnect, and tool results are rejected when the credential revision/settings/review change during execution.
- Before MCP initialization, valid access tokens are used; near-expiry tokens refresh once through the confirmed endpoint. Refreshes are deduplicated per connection/identity, use the existing granted scopes and resource, preserve an omitted refresh token or rotate one explicitly returned. No browser sign-in or scope step-up is started by Ask AI.
- Token requests are at most 32 KiB, responses 128 KiB; HTTPS, all-address public DNS validation and a socket pinned to one of those numeric addresses, with TLS SNI/certificate validation for the original hostname. No redirects, cookies, credential storage, caching or automatic replay. The pinned exchange deadline is 30 seconds; the overall deadline including DNS is 35 seconds. Errors never expose provider token/error payloads. Unknown token lifetime uses a conservative one-hour local deadline; explicit invalid/boolean/too-short/excessive lifetimes fail closed.
- Invalid/expired authentication refuses the MCP request. No tool operation is automatically replayed after 401/403 or token errors.
- Keychain writes/reads are serialized with a mutation lock, and refresh uses atomic compare-and-replace against its original credential. A disconnect/new token cannot be overwritten by a late refresh. In-memory credential revisions also prevent an authorization result from saving after configuration changes/disconnect/delete. Cancelled or closed editors stop their browser/check tasks before accepting late results.
- **この端末から接続を解除** removes local OAuth credentials, tool approvals, active inventory/client cache and in-flight refresh. It does not remotely revoke the provider grant. Provider-side revocation must be done in that service's own account settings; no revocation endpoint is guessed or contacted automatically.
- Personal project/record scopes and RecordAccessPolicy remain unchanged; OAuth is transport authentication, not permission to send private Memora content or execute writes. Existing approvals and execution caps remain in force.

## Limits and remaining work

This is **manually configured, preregistered public-client authorization**, not complete MCP authorization discovery. Protected-resource/authorization-server metadata discovery, issuer validation against fetched metadata, dynamic registration, confidential clients, automatic scope step-up and cross-host authorization/token endpoints are not implemented. The token audience itself is enforced by the resource server; the app binds local credentials and requests to the configured resource but cannot independently verify opaque-token claims.

The 2026-10-25 transport fix removes the DNS-check/URLSession re-resolution gap for MCP POSTs and OAuth token POSTs: `MCPPinnedHTTP` passes validated numeric addresses to `PinnedHTTPSConnection`, retaining original-host TLS verification. There is no hostname-resolution fallback or automatic retry. This bounds that client-side DNS rebinding path; it does not certify arbitrary servers or their tools. Memora-managed public distribution still needs a trusted backend for curated destinations, account authorization, server-enforced budgets and audit (design recommendation, not a deployed service). System-browser navigation during authorization remains controlled by the user's chosen authentication site; the app does not pin browser traffic.

The pinned client currently supports HTTP/1.1, identity content encoding and one approved IP per exchange. HTTP/2-only or compression-only endpoints, missing certificate intermediates that require network fetching, and automatic address failover are unsupported. Real provider/browser/device compatibility is unverified; failures do not relax TLS/public-address checks or replay a potentially side-effecting operation. SDK 0.12.1 and its 2025-11-25 protocol remain pinned; this is not a 2026-protocol migration.

Composio's authenticated backend, production billing enforcement and credentials-backed external E2E remain unconnected. No external account login, paid operation or remote revocation was performed during development.

## Verification

`tools/checks/run-tool-integration-checks.sh` runs four local suites. OAuth fixtures check endpoint/same-host/scope validation, resource and client identity separation, callback route/state/duplicate/code/error rejection, expiry, refresh preservation, scope-escalation rejection, Bearer type, malformed tokens and form injection encoding. These do not contact an OAuth provider or verify platform Keychain/browser behavior.

`tools/checks/run-mcp-pinned-http-checks.sh` additionally exercises production HTTP parsing, MCP transport and OAuth actors with injected DNS/wire bytes and fixture SDK symbols/keychain. It checks numeric destination binding, mixed-public/private DNS refusal, header injection/framing/size bounds, fragmented JSON/SSE, unfinished HTTP chunks, matching reply completion, empty notification/server-response acknowledgements, early session publication, session replacement refusal, disconnect/caller cancellation/late callbacks and OAuth stale-refresh CAS. Real SDK conformance is checked by Bitrig builds, separately from those fixtures. No external requests or credentials are used.

Build/UI outcomes for this increment are recorded after verification. Actual provider login, refresh rotation, revoked-token handling, ASWebAuthenticationSession redirects on a device, Keychain locked/write-failure races and full accessibility regression need credential/device tests. Build success alone does not establish those flows work.

Sources: [SDK PKCE](https://github.com/modelcontextprotocol/swift-sdk/blob/0.12.1/Sources/MCP/Base/Authorization/PKCE.swift), [SDK authorization code validation](https://github.com/modelcontextprotocol/swift-sdk/blob/0.12.1/Sources/MCP/Base/Authorization/OAuthAuthorizationCodeFlow.swift), [MCP authorization specification](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization).

## Results for this increment

- Final source build succeeded: `bitrig build -destination selected`, log `2026-10-13T15-26-39-4d14fd03.log`. One existing AppIntents metadata extraction warning; no compile/link errors.
- Four local suites passed through `tools/checks/run-tool-integration-checks.sh`: tool integration, Web search intent, conversation provenance, OAuth fixtures. Legacy MCP settings with no `oauth` field still decode.
- iPhone 18 Pro Max simulator: navigated Ask AI → attachment menu → integrations → MCP → add connection; confirmed Bearer mode remains the default; enabled OAuth and inspected the Client ID, endpoints, scopes, redirect, unauthenticated label and disabled Save/Sign-in controls for incomplete configuration. Inspected the light-mode form screenshot. Cancelled without saving; MCP list remained empty; returned to Ask AI. No account/token entered, no browser sign-in or external request initiated.
- Real OAuth/MCP E2E, refresh-token server rotation/revocation, Keychain storage failure/locked-device/concurrent mutation and browser cancellation on hardware remain unverified. Dark Mode, large Dynamic Type and complete accessibility/Glass regressions were not tested in this increment.
