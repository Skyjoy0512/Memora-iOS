# Ask AI integration foundation — 2026-10-13

## Implemented scope

Existing Ask AI, cloud provider sessions (Anthropic and OpenAI-compatible), on-device tool sessions, approval cards, record access policy, BYOK keys and all Glass/navigation components are retained.

- `AIToolDefinition` / `AIToolRegistry`: namespaced definitions, availability, enable state, permissions and risk. Existing internal tool names remain aliases for backward compatibility.
- `ToolInputValidator`: bounded JSON Schema subset; types, required fields, additional properties, enum, array/string/numeric bounds, anyOf/oneOf/allOf. Unsupported validation keywords such as `$ref`, regex and format fail closed. It is not a full JSON Schema implementation.
- `MemoraModel+ToolExecution`: 24 tool dispatches per answer, persistent 50 execution attempts/day/MCP server. Failed attempts count. SQLite write failure refuses execution. Cloud agent remains limited to 16 rounds. Limits are local safeguards, not a server billing guarantee.
- Official MCP Swift SDK **0.12.1**, pinned in Project.json. SDK handles protocol/client/listTools/callTool; bounded HTTP transport handles POST JSON/SSE, session headers, notifications before a matching response, LF/CRLF, cancellation, no cookies/cache, no redirects, 2 MiB responses, 64 KiB requests. Connection/list/call timeout is 35 seconds; HTTP resource timeout 30 seconds. No shell/process transport.
- Tool discovery is at most four pages/40 tools/server, 300-second cache; the agent receives at most 16 tools and 24 KiB total schemas. Selection is bounded registration order, not semantic plugin discovery yet.
- Changing endpoint/token revokes automatic-read approval. Endpoint must be manually checked before agent discovery. Only explicitly approved read fingerprints on declared-free servers can run automatically, and only without known private reads/memory/incomplete provenance. Changes, unknown charges and other calls use existing approval cards. Edited schema/description changes fingerprint. Already-started external side effects cannot be undone by disabling a connection.
- Unknown-charge servers only offer manually cached tools; agent initialization does not silently refresh their inventory. Disconnect/reset clears client caches. No automatic call retry. Remote JSON-RPC error payloads are normalized before display/LLM input, rather than echoing server-provided credentials or large bodies.
- HTTPS/public host checks, DNS answer checks for private/loopback/link-local/documentation/transition addresses. Each POST rechecks DNS off the main actor. DNS resolution and URLSession connection are separate: DNS rebinding is **not fully prevented**. Production needs a trusted egress proxy with IP pinning/allowlists. Custom arbitrary-server connection remains explicit user action, not registry trust.
- `IntegrationProvider` is the execution interface. `MCPIntegrationProvider` is operational code; `ComposioProvider` intentionally refuses execution until an authenticated backend exists. Existing Gmail/Notion adapters remain direct services and are labeled as such in the registry; they are not yet generalized behind this protocol.
- Services list/search/detail from composer attachment menu and Settings. Existing Gmail/Notion/MCP setup screens are reused. Individual Ask AI enable settings persist without deleting credentials. Google Drive and GitHub explicitly show unavailable. No extra tab; no changes to FAB, composer rendering, segmented control, Hero or scroll behavior.
- `read_calendar`: uses the existing authorized device calendar service, strict date parsing, max 30 event titles; no automatic permission prompt. It is not direct Google Calendar OAuth. Creation remains approval-gated.
- Three shipped skills: journal review, project organization, travel planning. Keyword selection, at most two procedures, bounded context; enable settings persist. `skillMarkdown` exposes compatible name/description frontmatter and Markdown instructions. No external package/ZIP loader, downloaded scripts, shell, permission escalation or automatic paid calls. The same tool gates apply regardless of skill.
- Registered models can explicitly disable function calling. New registrations default off; older missing flags preserve existing behavior. Normal grounded questions remain possible; unsupported tool actions refuse safely. Capabilities are user-configured, not remotely auto-detected.

## Existing service boundaries

Gmail uses existing OAuth PKCE and Keychain tokens; requires `MemoraGoogleClientID`. Notion is manual integration-token/page configuration; only page creation is implemented, with approval. Device calendar uses EventKit permission. MCP supports supplied Bearer tokens/public servers and now manually preregistered public-client OAuth with PKCE, ASWebAuthenticationSession and Keychain refresh tokens. Automatic metadata discovery, dynamic client registration and scope step-up remain unavailable. See [MCP_OAUTH.md](MCP_OAUTH.md) for the supported subset and verification limits.

Personal records remain in the existing store. Integration usage is additive at `memora.integrations.usage.v1`; no record migration/deletion. Connection and disable settings are preferences, secrets remain Keychain. Legacy MCP JSON decodes new optional policy fields as unknown/unreviewed, so explicit review is necessary after upgrading. Persisted usage is not yet exported in backup; it must not be relied on for commercial quotas.

External responses are bounded and prefixed as untrusted data, not instructions. Existing write approvals remain mandatory. Prompt instructions cannot guarantee that every model ignores injection; enforce grants/cost/risk server-side before commercial deployment. Known private context requires approval before remote MCP execution. Provenance becomes incomplete after external results, preventing unsafe reuse as verified record evidence.

## Required Memora backend contract (design, not deployed endpoints)

The repository has no authenticated integration backend. Composio admin keys/client secrets must never enter the app. The following paths describe a **Memora-owned future API**, not assumed Composio SDK methods:

| Contract | Responsibility |
| --- | --- |
| `GET /v1/integrations` | User-scoped approved services, state, grants, tool versions, remaining budget |
| `POST /v1/integrations/{id}/connect` | Allowed service/scope; return HTTPS OAuth URL with expiring state, bind verified identity |
| `DELETE /v1/integrations/{id}` | Revoke and remove user-specific tokens; no cross-user access |
| `GET /v1/integrations/{id}/tools` | Curated, version-pinned JSON Schema/risk/cost; exclude unauthorized tools |
| `POST /v1/tools/execute` | Verify user, grants, exact tool version, argument schema and approval receipt; atomically reserve budget/idempotency key before dispatch |
| `GET /v1/tools/executions/{id}` | Real result/status; interruption must not cause automatic side-effect replay |

Server authenticates the user independently of app-provided IDs; stores Composio credentials server-side; separates OAuth credentials from LLM BYOK keys; refuses missing approval, budget exhaustion, unknown cost, untrusted destinations and unsupported versions. Billing limits must be enforced before provider dispatch, not mirrored client counters. No production API calls or Composio accounts were created in this work.

## Outstanding work

1. MCP OAuth automatic discovery/issuer verification and dynamic registration; provider/account integration tests. Manual preregistered PKCE OAuth is implemented; see [MCP_OAUTH.md](MCP_OAUTH.md).
2. Implement/deploy the authenticated backend above, then Composio adapter E2E for one service. Drive/GitHub/Calendar OAuth remain unavailable until then.
3. Generalize existing direct services behind `IntegrationProvider`, semantic tool selection, safe full-schema compatibility where needed, structured MCP results/resources and richer reconnect states.
4. Curated remote catalog trust reviews; public MCP Registry search stays off. SDK 0.12.1 implements 2025-11-25 protocol; newer specification compatibility is not established by this build.
5. External Agent Skills package loading/review not implemented; initial catalog is compiled trusted text only.
6. Production server-enforced per-user metering, egress controls, rate limits and audit without secrets. Local daily limits can be reset by storage/device changes.

## Verification

- Bitrig simulator builds succeeded during integration (`12-36-00-d5091e04`, `12-40-00-6278d36d`), existing AppIntents metadata warning only. Final build/UI results are appended below.
- `ToolIntegrationChecks`: schema bounds/types/enum, unknown/disabled tool rejection, registry collisions, SSE notifications/ID matching/LF/CRLF, legacy MCP decode, namespace/fingerprint, public/private IP classification, skill selection/disable, DNS cancellation/late-result single completion, unconfigured Composio refusal. Pure local fixtures; no network account operations.
- `AIWebSearchIntentChecks`: passed; natural Web search/internal-scope/negation/follow-up routing unchanged.
- Reproducible local runner: `tools/checks/run-tool-integration-checks.sh`; all three suites passed.
- `AIConversationProvenanceChecks`: passed; revoke/edit/missing-source/workspace/memory/legacy checks.
- Actual remote MCP/OAuth, Gmail, Notion, paid LLM and Composio E2E were **not run**. No live external account data was fetched and no paid tool call was made. Build success does not establish those features work.

## Official research

- [Swift SDK 0.12.1](https://github.com/modelcontextprotocol/swift-sdk/tree/0.12.1), MIT license included in app resources; SDK supports HTTP and OAuth, minimum iOS 16 (app targets 18).
- [MCP specification](https://modelcontextprotocol.io/) and [public registry](https://registry.modelcontextprotocol.io/): registry presence is not a trust grant.
- [Composio tool execution](https://docs.composio.dev/docs/tools-direct/executing-tools): per-user execution and version pinning must be implemented at the backend.
- [Pricing](https://composio.dev/pricing): free-tier limits and paid per-call/add-on pricing vary by account/app choice. Do not presume an integration is free based on brand name.
- [Current terms](https://composio.dev/terms) describe personal/commercial use subject to terms/fair use; an older [terms page](https://composio.dev/terms-of-service/) still mentions non-commercial use. Confirm applicable contract before commercial activation. No agreement was accepted here.
- [Agent Skills specification](https://agentskills.io/specification): compatible text metadata does not authorize tool access or executable code.

## Final verification for this increment

- Final source build: `bitrig build -destination selected`, success. Log `2026-10-13T12-56-45-d2a481e7.log`; one existing AppIntents metadata-extraction warning, no compile/link errors.
- Local runner passed all three suites, including the unconfigured Composio provider refusing both discovery and execution.
- iPhone 18 Pro Max built-in simulator: opened Ask AI → attachment menu → integrations sheet; viewed the monochrome native list; searched `Gmail` and obtained only that service row; opened GitHub detail and confirmed unavailable/no connection action; opened Gmail detail and switched its actual native switch off/on, restoring its original enabled value; opened all three shipped skills; cleared search and returned to Ask AI. No sign-in, token entry, external data query, AI model execution or paid action.
- One initial UI assertion targeted the enclosing switch accessibility element rather than the inner native switch and did not change the value. Retesting the native switch verified the value changed off/on. No app fix was needed for that test-selection error.
- Screenshot inspected: light-mode services list, native sheet close button/search field, no overlapping labels on this device. Existing Ask AI entry/menu and three-tab/FAB controls remained accessible. This is not full regression proof for recording, actual tool execution, animation timing or all screens.
- Dark Mode, larger Dynamic Type, VoiceOver operation, Reduce Transparency/Motion, device-calendar retrieval, actual MCP/OAuth and external-account workflows remain unverified at runtime in this increment. No device tests were run.
- Next work: MCP OAuth and authenticated Composio backend integration, full direct-provider abstraction, semantic catalog/tool filtering, then credential-backed E2E and accessibility/Glass/device regression testing. The full plugin request is not complete yet.
