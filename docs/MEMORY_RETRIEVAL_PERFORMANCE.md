# Memory retrieval: bounded in-memory FTS reuse

Measured on 2026-10-22. Raw samples and environment are in
`qa/memora-1.0/phase4/memory-benchmark.json`.

The benchmark calls the production retrieval function twice per sample
(semantic memory, then episode history). Each kind has 2,000 deterministic
candidates, of which 1,600 match the workspace/person boundary. Three query
pairs rotate across 21 warm samples. Three interleaved before/after rounds
returned the same result checksum and passed the same scope assertions.
No app records, provider calls, network, or credentials are used.

| Host statistic (median of three rounds) | Before | After |
| --- | ---: | ---: |
| Warm pair median | 40.646ms | 1.966ms |
| Warm pair p95 | 44.581ms | 2.315ms |
| Cold pair | 43.608ms | 42.897ms |
| Maximum process RSS | 12,386,304 bytes | 13,418,496 bytes |

Warm median time fell 95.16%. The cost is about 0.98MiB more median maximum
host RSS. Three cold samples do not establish an improvement in first-use
latency. This is not an iOS frame-rate, end-to-end input-latency, app-memory,
energy, battery, or AI-answer-quality measurement. Candidate generation and
provenance checks in the model are outside the timed region.

## Safety and lifetime

- Every lookup still filters the supplied candidates by exact workspace and
  person, bounded to the same first 5,000 records as before.
- Reuse requires the entire ordered `MemoryRetrievalItem` array to match,
  including text, kind, update time, source ID and scope. Changed snapshots
  discard their old index before attempting a replacement. Failure throws;
  it never falls back to an older snapshot.
- At most two indexes are retained, to support alternating semantic/episode
  requests. Admission requires <=2MiB of source UTF-8 and a combined <=16MiB
  estimate (source text, value storage and SQLite page-cache allocation).
  This is an admission estimate, not a hard process-RSS limit. Larger inputs
  are still searched normally, but their indexes are disposed afterward.
- Inactive indexes expire after 60 seconds, checked on the next lookup.
  Workspace/person changes, an empty authorized snapshot, disabling memory,
  and model record/privacy/memory changes also invalidate retained indexes.
  Updating history invalidates episode indexes without evicting unchanged
  semantic memory. No plaintext index is persisted to disk.
- One mutex confines all SQLite operations and lifetime management. Concurrent
  callers cannot query or invalidate a connection at the same time.
- Query grams are calculated once for overlap checks. FTS terms, per-record
  tokenization, ranking/tie rules, hit and query bounds are unchanged.

`MemoryRetrievalChecks` tests snapshot edits, source/date changes, ordering,
semantic/episode alternation, targeted/explicit invalidation, empty deletion,
workspace/person boundaries, expiry, oversize admission and concurrent reads.
The final checks also compile and run in Swift 6 mode. The app remains Swift 5.

## Reproduce

Compile with the same compiler, optimization, fixture and SQLite library:

```sh
task_benchmark_dir=$(mktemp -d /Volumes/WorkspaceSSD/Development/Temp/memora-memory-bench.XXXXXX)
git archive 8699e76 App/MemoryRetrievalOrchestrator.swift App/MemoryRetrievalItem.swift |
  tar -x -C "$task_benchmark_dir"
swiftc -O -swift-version 5 -parse-as-library \
  "$task_benchmark_dir/App/MemoryRetrievalOrchestrator.swift" \
  "$task_benchmark_dir/App/MemoryRetrievalItem.swift" \
  tools/checks/MemoryRetrievalBenchmark.swift -lsqlite3 -o "$task_benchmark_dir/before"
swiftc -O -swift-version 5 -parse-as-library \
  App/MemoryRetrievalOrchestrator.swift App/MemoryRetrievalItem.swift \
  tools/checks/MemoryRetrievalBenchmark.swift -lsqlite3 -o "$task_benchmark_dir/after"
/usr/bin/time -l "$task_benchmark_dir/before" 2000
/usr/bin/time -l "$task_benchmark_dir/after" 2000
```

Repeat in reversed order and then original order, without concurrent builds,
test runs or profiling. Retain every result, not only the fastest sample.

## Remaining performance work

Cold reconstruction is still synchronous at the caller (currently MainActor).
Authorization/provenance checks and candidate generation are intentionally
not bypassed. History writes, data edits or frequent privacy changes can reduce
cache reuse. Moving this path off MainActor needs a captured scope/revision
and revalidation after await, plus a real UI latency measurement.

Existing settled-Markdown/structured-component caches, collection grouping and
batched task-ownership optimizations predate this change. Their benchmark
results are not counted as new improvements. Long streaming Markdown,
attachments, large histories, project search and agent activity still require
iOS Instruments/physical-device frame, allocation and energy measurements.
