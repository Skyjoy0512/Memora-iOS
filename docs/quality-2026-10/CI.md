# GitHub Actions investigation — 2026-10-25

## 2026-10-26: executed CI failure isolated and repaired

Freshly fetched main/HEAD: `cb23b3dfab31cf6521b393cd6864171eb1ce5682`, clean tree before this work. [Run 40240509909](https://github.com/Skyjoy0512/Memora-iOS/actions/runs/40240509909) actually executed all six suites: five passed; optimization failed. Downloaded its `host-quality-results` artifact; `optimization.log` identifies the collections binary SIGTRAP, not workflow parsing or Swift compilation.

Instrumented the existing section equality precondition (no assertion removed). In an `en_US` child process it reports count=100, matching section IDs/order, but Japanese current month headings versus legacy `Sep 2026` / `Aug 2026` / `Jul 2026`; that equality is false. The unchanged comparison in `ja_JP` passes. Locally the failing precondition leaves the crash reporter waiting, so the reproduction process was bounded at 30 seconds and failed with timeout; this is distinct from the CI's observed SIGTRAP.

Fix: only the historical presentation expression `date.formatted(.dateTime.year().month())` is normalized to the already-shipped Japanese `MemoraFormat.monthTitle`. Both extracted candidates receive one fixed Gregorian/UTC calendar and evaluation date. Full section equality and ranking equality remain, and independent exact Japanese heading assertions are added. App code/UI is unchanged. The default runner now requires **both en_US and ja_JP** in fresh child processes with UTC; `--locale` permits isolated reproductions. No persistent host locale setting is written.

Local `run-performance-checks.py` passes both locales and performance-log checks. The full optimization and remote six-suite re-run are tracked below as results become available; neither is presumed successful from this targeted pass.

## Earlier investigation (historical)

Status: workflow fix implemented; remote re-run **Not Run** (not pushed/dispatched by this session).

- GitHub main inspected/fetched: `23230af5e0356a1a5f7d8d4e72ed22b5d937d704`.
- [Latest existing run](https://github.com/Skyjoy0512/Memora-iOS/actions/runs/40149268122): completed/failure, zero jobs. There is no executed Swift test log to attribute this failure to app code.
- `.github/workflows/quality.yml` used `${{ runner.temp }}` in `jobs.host-checks.env`. GitHub's [context availability table](https://docs.github.com/en/actions/reference/workflows-and-actions/contexts#context-availability) does not allow `runner` there; it does allow it in `jobs.<job_id>.steps.env`.
- Moved those five environment variables to the host-check step and create their directories there. Kept pinned actions, assertions, all six production host suites, actual-log artifacts and the Xcode 27 runner. No test skips were introduced.
- `xcode-27` is intentional, not a guessed invalid label: [GitHub runner announcement](https://github.blog/changelog/2026-10-15-xcode-27-runner-image-generally-available/).

Local verification: `python3 -B tools/checks/test_quality_runner.py` (runner unit tests); final full-suite results are recorded in `C_TESTS.md`. A local pass is not proof of remote CI success. Bitrig publishes commits; no separate `git push` or billable hosted-run dispatch was performed.

Follow-up re-check after resuming work: fetched GitHub main again and queried the latest three runs. Main remains `23230af5e0356a1a5f7d8d4e72ed22b5d937d704`; latest run remains `40149268122` / completed / failure. No new remote result was available. The newly added `run-mcp-pinned-http-checks.sh` is included in the existing next-generation suite, not a skipped/optional gate. All six local suites passed in `memora-quality-ns8tghh9`; the final bounded-diagnostic change was separately revalidated. This does not mark the unexecuted remote CI fix as verified.
