# Legacy Hindsight integration reference — not an enabled app feature

Exact first-party files from `memora` commit `36c97e1` (feature originally `0703702`).
These `.swift.txt` files are reference material outside App/Shared and are not compiled or wired into the app.
No Hindsight server, dependency, account, token or external request was installed or executed.

The legacy extension automatically retains questions/answers and recalls from a fixed bank, without the
current workspace/source permission revalidation, explicit paid-tool approval, deletion invalidation,
bounded shared run budget or sensitivity policy. It also asks the model to treat returned facts as confirmed.
Restoring that runtime would regress the current privacy and memory design.

Future work must use the existing registry/approval and provenance architecture, isolate each workspace,
validate endpoint/redirect/auth and cost, limit requests/results/time, revalidate immediately before sending,
and support memory deletion/revocation. Never enable it just because the old stored setting is true.
The source configuration and Keychain data are not migrated, read, deleted or sent by this integration.
Current Swift/SQLite semantic/episodic memory remains the app's implementation.
