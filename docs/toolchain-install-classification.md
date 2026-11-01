# Toolchain install classification: eager, background or on-demand

Working table for #631, deciding from ADR-0021 principle 2: minimise the seconds
a **watching** user waits because of tooling. This file is the evidence and the
provisional reading of it. The decision and its ADR amendment come after the
data columns marked *pending* are filled.

## What is known now

One bootstrap manifest, from a cache **rebuild** (`cache=rebuild`) in a
`claude-cloud-sandbox` on 2026-11-01, `total=132s`. Single sample: it says where
the seconds go, not how often.

| Step | Seconds | Where it lands |
| --- | --- | --- |
| `toolkit` | 3 | before the first prompt |
| `gcloud` | 3 | before the first prompt |
| `precommit` (all binaries below) | 27 | before the first prompt |
| `precommit-warm` (pre-commit hook environments) | **96** | before the first prompt |
| `devknowledge`, `golangci`, `shims` | 2 | before the first prompt |

The per-tool binary installs are small. The warm is 73% of the rebuild.

| Tool | Install s | Route | Used this session |
| --- | --- | --- | --- |
| markdownlint-cli2 | 5 | npm | yes |
| semgrep | 8 | uv/pip | not seen |
| cspell | 4 | npm | not seen |
| checkov | 4 | uv/pip | not seen |
| terraform | 3 | release zip | not seen |
| actionlint | 1 | release tarball | yes |
| tflint | 1 | release zip | not seen |
| pre-commit | 1 | uv/pip | yes |
| shellcheck, gitleaks, tflint-ruleset-google | 0 | release | shellcheck yes, others not seen |

"Used this session" comes from this session's local spool (`shims/first-use`),
which is one session, so it is an illustration of the column, not a value for it.

## What is missing, and why

The per-tool decision needs three numbers per tool, from the #625 data:

| Column | Definition | Status |
| --- | --- | --- |
| P(used) | share of sessions with a shim event for the tool | **pending** |
| Rebuild rate | share of sessions with `cache=rebuild` in the `session shape` event | **pending** |
| Watched wait | seconds of waiting on the tool inside a watched stretch (a prompt within 60s of a `Stop`), from shim `duration_ms` and `blocked_ms` | **pending**, and `blocked_ms` is 0 until an installer exists, so the *background* side is a prediction |

The aggregated records are in the telemetry bucket, and the identity that writes
them cannot read them by design (`docs/cloud-sandbox-design.md` section 6). Reading
needs a human-approved grant on that bucket, which this session did not request.
The window is also about 10 days since #625 closed on 2026-10-22, against the two
weeks the issue asks for.

## Provisional reading, from the design alone

Not a classification. It says which rows the data is most likely to move.

- **`precommit-warm` (96s) is the decision that matters.** Warming is
  a cache of hook environments that only a commit uses, so it is the clearest
  candidate for background. The risk the issue names holds: a commit that finds the
  warm unfinished must wait on the installer, not install inline (about 65s in one
  agent Bash call, near the 120s foreground timeout).
- **The 27s of binaries are cheap either way.** They are cheap enough that moving
  them to background mostly buys complexity. The expected outcome is eager for the
  tools nearly every session uses (`pre-commit`, `shellcheck`, `actionlint`,
  `gitleaks`) and the rest decided on P(used).
- **`terraform`, `tflint`, `checkov`** are used only in Terraform repos. They are
  the likeliest on-demand or background rows, and they already carry the
  `NOT CHECKED` reporting when absent.
- **`gcloud`**: the issue notes it is now preinstalled in the image, so #323's
  premise is stale. Confirm against the image before folding #323 in.

## To finish

1. Obtain read access to the telemetry bucket (a human decision) and fill the three
   columns for every tool in `home/standards/tools.json`.
2. Classify each tool, with watched wait as the stated criterion.
3. Record the classification as an ADR-0021 amendment, update
   `docs/cloud-sandbox-design.md` section 5, then build the installer and
   `SessionStart` wiring for the background tools and re-measure `timings=`.
