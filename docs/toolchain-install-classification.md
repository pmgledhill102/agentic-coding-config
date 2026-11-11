# Toolchain install classification: eager, background or on-demand

The evidence behind #631's per-tool decision, judged by ADR-0021 principle 2:
minimise the seconds a **watching** user waits because of tooling. The decision
itself is recorded in [ADR-0021](../adrs/0021-agent-sandbox-toolchain-principles.md)'s
2026-11-10 amendment. This file holds the numbers it rests on.

## Source

The agent-telemetry digest (#625, #631), read on 2026-11-10 under a human-approved
read-only grant. Windows by record type:

| Records | Window | Population |
| --- | --- | --- |
| Session markers (cache verdict) | 2026-10-19 .. 11-09 | 103 distinct sessions |
| Bootstrap records and per-step timings | 2026-10-19 .. 11-08 | 88 container builds |
| Shim and hook events | 2026-10-23 .. 11-09 | 48 sessions (the P(used) denominator) |

Sessions are counted distinct, because each session's marker is spooled several
times (#736). `blocked_ms` is 0 on every shim row, as expected while nothing
installs in the background, so the background column is a **prediction** from
first-use times, not a measurement. The manifest `timings=` line after the change
is what confirms or refutes it (principle 3).

## Definitions

- **Session start**: the session marker's time. The first prompt arrives p50 3 s
  after it (p90 40 s), so the bootstrap has already finished by then. **On a
  rebuild, setup time is watched time.**
- **Rebuild rate**: share of sessions whose cache verdict is `rebuild`.
- **P(used)**: share of the 48 sessions with at least one shim event for the tool.
- **First use**: the earliest shim event for the tool, in seconds after session start.
- **Watched turn**: the next prompt arrives within 60 s of the turn's `Stop`. 311 of
  1197 turns (26%) qualify.
- **Eager watched wait**: rebuild rate × mean install seconds, all of it before the
  first prompt.
- **Background watched wait**: for each session whose first use falls in a watched
  turn before the installer finishes at time D, `D − first use`. Summed, then
  divided by 48.

## Rebuild rate

**72%** (74 of 103 sessions), and 77% in the 48-session event subset. A rebuild is
the normal case, not the exception, so most sessions pay their setup time while
someone waits for the first prompt.

Mean setup seconds per build (n=88): `total` 136, `precommit` (binaries) 52.5,
`precommit-warm` (hook environments) 73.5. Eager `precommit` plus
`precommit-warm` therefore costs **0.72 × 126 ≈ 91 watched seconds per session**.

## Per tool

| Tool | P(used) | Install p50 / p90 / max s | First use p10 / p50 s |
| --- | --- | --- | --- |
| pre-commit | 0.77 | 2 / 9 / 18 | 35 / 505 |
| gitleaks | 0.73 | 1 / 1 / **65** | 42 / 697 |
| shellcheck | 0.48 | 0 / 1 / 2 | 86 / 1631 |
| cspell | 0.42 | 5 / 6 / 41 | 33 / 908 |
| actionlint | 0.35 | 0 / 1 / **65** | 56 / 1967 |
| markdownlint-cli2 | 0.33 | 5 / 6 / 14 | 119 / 838 |
| semgrep (binary) | 0.23 | 16 / 35 / 95 | 33 / 235 |
| terraform, tflint | 0.04 | 1–3 / 1–3 / 3–5 | first use ≥ 505 |
| checkov | 0.04 | 5 / 28 / **308** | first use ≥ 524 |
| hadolint, trivy | 0.10–0.20 (shimmed from 11-06; n=10) | 1–2 / 1–4 / 1–4 | first use ≥ 18000 |
| golangci-lint, tflint-ruleset-google, gh | not shimmed | 1–2 / 1–6 / 2–36 | – |

The bold maxima are download stalls, not install work.

## The hook-environment warm

| Part | p50 s | p90 s | max s |
| --- | --- | --- | --- |
| Standard set (`cloud/precommit-warm.yaml`) | 24 | 32 | – |
| Per cloned repo, when present (46 of 88 builds) | 74 | 246 | – |
| of which `warm.<repo>.semgrep` (6 repos) | 29 | 141 | 329 |
| of which `warm.<repo>.golangci-lint` (one Go repo) | 72 | 96 | 127 |

The variable part of the warm is the per-repo upstream semgrep hook and the Go
linter's environment, not the standard set. #739 removes the semgrep part at its
source.

## When a commit first needs the toolchain

| Measure | n | p10 | p25 | p50 | < 45 s | < 85 s | < 288 s |
| --- | --- | --- | --- | --- | --- | --- | --- |
| First commit | 40 | 36 | 175 | 723 | 5 | 5 | 12 |
| First `pre-commit` run | 37 | 35 | – | 505 | 5 | 7 | 13 |

The distribution has two clusters. About an eighth of committing sessions commit
within 45 s, which looks like pre-briefed or unattended work, and most of those are
not watched turns. The median is 10–12 minutes. Only 2 sessions run `pre-commit` in
a watched turn before 84 s.

## Eager against background

One background installer covering the binaries and the warm, started at
`SessionStart`, finishing at time D:

| D | Watched wait per session |
| --- | --- |
| 45 s (binaries, p50) | 0.3 s |
| 85 s (binaries plus warm, p50) | 1.8 s |
| 288 s (binaries plus warm, p90, applied to every session) | 20.6 s |
| 458 s (max, applied to every session) | 43.6 s |

Against **91 s eager**, background wins even at the pessimistic all-p90 bound. The
comparison is asymmetric by construction: eager counts all setup as watched, while
background applies the 60 s test. Counting every early first use as watched removes
that asymmetry, and the result is 8.7 s per session at D=85 and 61 s at D=288.
Background still wins.

Background has two costs that this table doesn't show:

- It competes with the agent for CPU and network, so D in practice may be longer
  than these build timings.
- It is repeated in every session that needs it, cache hits included, because a
  mid-session install is not snapshotted. About 28% of sessions are cache hits that
  currently get the toolchain for free. That cost is unwatched, which is why
  principle 2 accepts it.

## Classification

The decision is the ADR-0021 amendment. In summary:

| Class | Tools | Why |
| --- | --- | --- |
| **eager** (setup script) | toolkit, helpers, skills, shims, gcloud, gh, the global git hook | Always needed, single-digit seconds, and part of what the first prompt itself uses. The git hook must be in place before the first commit, so that a commit waits for the toolchain instead of skipping it. |
| **background, first in the queue** | pre-commit, gitleaks, shellcheck, actionlint | High P(used) but tiny installs, so eager and background tie at p50. The 65 s stall tail decides it: eager puts a stall on the first prompt, background puts it before a first use that is p10 35–86 s away. |
| **background** | cspell, markdownlint-cli2, semgrep, hadolint, trivy, terraform, tflint, tflint-ruleset-google, checkov, golangci-lint, the hook-environment warm | Low P(used), first use far later than the install, or both. Eager buys nothing for them. |
| **on-demand** | none | An inline install inside a commit runs within one agent Bash call, close to the 120 s timeout. Background with a waiting commit is strictly better. |

Predicted effect: on a rebuild, watched setup wait falls by about 129 s (the mean of
`precommit`, `precommit-warm` and `golangci`), which is about 93 s per session at the
72% rebuild rate. In exchange, background adds about 2 s per session of watched
wait at a median install.

## Data limits

- 18 days of event data from 48 sessions.
- The Terraform, Docker and Go rows rest on 1–2 sessions each.
- "Watched" is inferred from prompt timing, so an unattended session and a user who
  walked away look the same.
- `gh`, `golangci-lint` and the tflint plugin are not shimmed, so their P(used) is
  unmeasured.
- One of the two degraded builds recorded an empty `degraded=` field after aborting
  6 s in. That's a recording gap, filed separately.
