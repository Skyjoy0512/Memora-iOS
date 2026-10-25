# GitHub Actions investigation — 2026-10-25

Status: workflow fix implemented; remote re-run **Not Run** (not pushed/dispatched by this session).

- GitHub main inspected/fetched: `23230af5e0356a1a5f7d8d4e72ed22b5d937d704`.
- [Latest existing run](https://github.com/Skyjoy0512/Memora-iOS/actions/runs/40149268122): completed/failure, zero jobs. There is no executed Swift test log to attribute this failure to app code.
- `.github/workflows/quality.yml` used `${{ runner.temp }}` in `jobs.host-checks.env`. GitHub's [context availability table](https://docs.github.com/en/actions/reference/workflows-and-actions/contexts#context-availability) does not allow `runner` there; it does allow it in `jobs.<job_id>.steps.env`.
- Moved those five environment variables to the host-check step and create their directories there. Kept pinned actions, assertions, all six production host suites, actual-log artifacts and the Xcode 27 runner. No test skips were introduced.
- `xcode-27` is intentional, not a guessed invalid label: [GitHub runner announcement](https://github.blog/changelog/2026-10-15-xcode-27-runner-image-generally-available/).

Local verification: `python3 -B tools/checks/test_quality_runner.py` (runner unit tests); final full-suite results are recorded in `C_TESTS.md`. A local pass is not proof of remote CI success. Bitrig publishes commits; no separate `git push` or billable hosted-run dispatch was performed.
