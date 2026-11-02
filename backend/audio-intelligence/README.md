# Private audio accounting core

This folder is not a deployed service. It has no HTTP handler, provider keys,
default entitlements, enabled price seed, purchase flow, upload bucket or app
connection. Memora-provided transcription remains unavailable.

`ledger.sql` is a SQLite/D1-oriented migration. One insert reserves funds in the
account and fleet budgets atomically through triggers. Constraint failure rolls
back both updates. Immutable price revisions, independent STT/AI quotas, pending
and running limits, monthly request ceilings and append-only transition records
bound execution. Prices must be reviewed, enabled and have an expiry. An expired
or revoked entitlement/price also prevents dispatch after a reservation.

`ledger.mjs` wraps D1 prepared statements. Only the caller receiving a row from
`claim` may dispatch; redelivery cannot claim a running/settled request again.
An interrupted running request retains its ceiling until provider reconciliation;
unknown usage settles at its entire ceiling. Unsent reservations can release.
Confirmed over-ceiling usage must trip a provider circuit breaker and be recorded
as an operational overrun; do not discard that bill or automatically retry it.

The adapter is internal. Before calling it, a server must verify authentication,
App Store transaction/appAccountToken ownership and current entitlement, source
ownership/consent revision, decoded audio duration, model/token/tool ceilings and
request pricing. Compute the canonical request hash on the server. A client-sent
amount, plan, consent flag or subject is never authoritative. No such API is
implemented here. Do not deploy this core as an authenticated production service.

Validation:

```sh
python3 -B backend/audio-intelligence/test_ledger.py
node --check backend/audio-intelligence/ledger.mjs
```

The tests use real SQLite and independent concurrent connections. They exercise
reserve/settle/refund, uncertain bills, duplicate requests, global rollback,
parallel limits, price/entitlement refusal and immutable audit. They do not test
D1, the JavaScript binding against a live database, authentication, receipts,
provider dispatch, R2 expiry/deletion, or crash recovery of a deployed worker.

See [operating requirements](../../docs/AUDIO_CLOUD_OPERATIONS.md) before adding
an API or enabling paid execution. Run D1 staging tests and add verified purchase,
revocation, price drift, hard budget, request rate and deletion evidence first.
