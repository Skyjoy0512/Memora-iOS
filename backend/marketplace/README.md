# Memora community marketplace (Firebase)

Deployable backend and native client adapter; no Firebase project or credentials are included.
The app remains usable without it, shows no fabricated community posts/counters and keeps local sharing available.
This does not replace Memora's personal account, plans or team backend.

## Data and trust boundary

`functions/index.js` exports the HTTPS function `marketplace` in `asia-northeast1`.
Every write verifies a Firebase Auth ID token (including revocation), requires a verified email,
and derives the author/event owner from that verified identity. Email/password Auth is used by
`FirebaseCommunitySession`, with the refresh token in Keychain; the password is never persisted.
The mobile client never receives an Admin key. The two public client configuration values are
`MemoraMarketplaceURL` and `MemoraFirebaseAPIKey` in the app target's Info.plist properties in Project.json.
Do not put service-account credentials there.

Direct Firestore reads/writes are denied by the supplied rules; the Admin-backed API owns counters,
visibility and moderation state. Definitions are bounded to 32KB and a reviewed tool allowlist;
no executable package, endpoint or permission grant is installed. The allowlist is versioned beside
AgentTool and must be reviewed when that registry changes. Installation validates again in Swift,
saves with existing SQLite model methods and preserves an already edited local copy.

- New posts enter `pending`. Only an operator using Admin credentials can make them `published`.
  List exposes published posts; `mine` exposes only the authenticated author's posts.
- Like requests set the desired state. One event document per account/post and a transaction prevent
  retry/concurrency double counts. Download is counted only after the app confirms its local save,
  using a previously issued receipt/version. Each account contributes at most one addition per post.
  Counts measure accounts that added an item, not unique humans or file-transfer attempts.
- Popularity score is `likes * 3 + downloads`; only the server sets it. Newest uses the server creation time.
- Pages contain at most 20 posts and a server snapshot cursor. No unbounded catalog scans.
- Reports deduplicate by account. Three distinct reports quarantine the post; the operator reviews reports.
  An author can withdraw their own post. Blocking an author is a local display preference, reversible in account settings.
- Publication is idempotent by request UUID/content and limited to 10 new posts/account/day.
  Reactions/download operations are limited to 200/account/day. Banned accounts use the
  `marketplaceBanned` Auth custom claim. These are account quotas, not comprehensive anti-abuse protection.

No meeting, transcript, recording, API key, chat history or photo is part of a definition upload.
The publish sheet previews the exact definition and requires agreement to public-content rules.

## Deployment

Use a Firebase project with Firestore Native mode, Email/Password Authentication enabled and
Cloud Functions deployment enabled. Nothing here creates an account, enables billing or deploys automatically.
From this directory, with a project you control and Firebase CLI authentication already completed:

```sh
npm ci --prefix functions
npm test --prefix functions
npx firebase-tools deploy --project YOUR_PROJECT --only firestore:rules,firestore:indexes,functions:marketplace
```

Merge the two marketplace collection rule blocks into existing project rules if that project has other services.
Set `MemoraMarketplaceURL` to the deployed HTTPS function URL and `MemoraFirebaseAPIKey` to that project's
Web API key via Project.json (then run `bitrig preview -platform iOS`). No bundle ID, CloudKit entitlement
or Firebase Swift package is necessary for this REST adapter.

Register a community account in the app, follow the verification email and choose メール確認を反映.
Submit a definition. In Firestore Console an operator reviews `marketplacePosts/<id>` and its definition,
then sets `status` to `published` for an approved post, or `removed` for a rejected one.
Do not edit likes/downloads/score during review. A quarantined post stays hidden until reviewed.
Operators must monitor reports and respond to rights/abuse requests before a public launch.

## Checks and limits of verification

`bash tools/checks/run-marketplace-checks.sh` from the repo root exercises all bundled definition round trips,
legacy tool preservation, bounded imports and rejected unknown tools, plus the production API logic.
Node tests use a serialized transaction fixture with injected verified identities; they do **not** establish
Firestore isolation, actual Firebase Auth, deployed indexes or security rules behavior. A Java runtime is not
installed in this workspace, so the official Firestore emulator could not be run here.
An opt-in actual Firestore emulator check is provided below; use Java 21+ with Firebase CLI:

```sh
npx firebase-tools emulators:exec --project demo-memora --only firestore 'cd functions && npm run test:emulator'
```

Production connection, email delivery, two-device counters and real moderation need a configured Firebase project.
Firebase's official [ID token verification](https://firebase.google.com/docs/auth/admin/verify-id-tokens),
[Auth REST protocol](https://firebase.google.com/docs/reference/rest/auth/), and
[transaction behavior](https://firebase.google.com/docs/firestore/manage-data/transactions) informed this adapter.
