# Environment conformance

Every capability decision in this repo rests on platform behaviours that were
measured once, in a vendor environment that changes without notice:

- which egress lanes are open
- whether a container-written `settings.json` is honoured
- which tools the image ships

When one of them changes, the mechanism built on it stops working, the session
still looks normal, and nobody notices.
[#260](https://github.com/pmgledhill102/agentic-coding-config/issues/260) is
the response. This page covers the parts that are built: the script-checkable
assertions and the per-session fast run
([#653](https://github.com/pmgledhill102/agentic-coding-config/issues/653)),
and the checks only the agent can make
([#654](https://github.com/pmgledhill102/agentic-coding-config/issues/654)).

## Pieces

| Piece | Path | Deployed to |
| --- | --- | --- |
| Capability matrix, as data | `home/conformance/matrix.conf` | `~/.claude/conformance/matrix.conf` |
| Probe runner | `home/bin/env-conformance` | `~/.claude/bin/env-conformance` |
| Per-session fast run | `conformance` section of `start-session-gather-state` | runs in `/start-session` (step 5d) |
| Agent-observable checks | `home/skills/env-conformance/SKILL.md` | `/env-conformance` |
| Behaviour tests | `tests/env-conformance-test.sh` | CI only |

The bootstrap installs the runner and matrix in a sandbox, and chezmoi
installs them on a workstation. The matrix records sandbox measurements only,
so on a workstation the runner reports `not-applicable`.

## The matrix

Each stanza is one assertion. The format is documented at the top of the file.
Each stanza holds:

- the probe, and the result it should give
- a **negative control**
- the date the result was last observed
- the surface it was measured on
- what depends on it

A skill or doc that relies on a platform fact should cite the stanza id rather
than restate the measurement. A restated measurement goes stale with nothing
to flag it, and the matrix is re-measured.

### Why every entry has a control

Verifying the harness hook for #254 took three attempts. The first two each
gave a confident wrong answer: one linted the wrong repository, the other
checked a staged set that was not staged yet. A check that cannot fail tells
you nothing when it passes.

So each control runs **the same probe function** with an input that must give
a different observation. For example:

- a reachable host's control is a `.invalid` host
- a blocked host's control is a known-reachable one
- a present tool's control is a name that cannot exist

A probe whose control returns the expected value too is reported `unproven`,
never `pass`. The runner rejects a control that goes through a different
function, because that would prove the wrong function can fail.

## Statuses and exit codes

| Status | Meaning | Exit |
| --- | --- | --- |
| `pass` | Observed the expectation, and the control observed something else | 0 |
| `FAIL` | Observed something else. Printed with the stanza's `depends`, so it names what just became false | 1 |
| `unproven` | Observed the expectation, but so did the control, or the control could not run | 2 when nothing failed |
| `unknown` | The probe could not ask: no network, no `gh`, no session id. Not a failure | 0 |
| `invalid` | A malformed stanza. Checked before the surface filter, so a broken entry never just drops out | 3 |

The brief mode's `state=` adds `unknown`, for a run where nothing applicable
could be asked, and `not-applicable`, for a surface with no entries. Neither
reads as `ok`, because nothing was confirmed.

### Telling broken from unknown

The egress proxy refuses a host at `CONNECT` with a 403. curl reports that as
`%{http_connect}`, separately from anything the origin returns inside the
tunnel, so it is classed `blocked`. A DNS failure, refused connection or
timeout is `unknown`: there was no network to ask, which is not the proxy
saying no. `gh` errors work the same way: an `(HTTP 403)` is an answer, and an
error without a status is not.

## Run modes

- **Fast** (`--fast`): the `mode=fast` stanzas. It takes about 2 seconds and
  needs no human and no approvals. `/start-session` runs it on every session
  (`--fast --brief`), and each `FAIL` becomes a "Needs attention" line naming
  what it invalidates.
- **Full** (the default): every stanza, about 6 seconds. Run it by hand
  (`~/.claude/bin/env-conformance`), or let the scheduled run do it
  ([#655](https://github.com/pmgledhill102/agentic-coding-config/issues/655)).

Every probe is read-only: an HTTP request, a command lookup or a file read.
The test suite checks that a full run leaves `HOME` and cwd unchanged. A probe
that needs a human, or must plant something to observe it, belongs only in the
scheduled suite, never in this matrix.

## Agent-observable checks

Two load-bearing claims can only be checked from inside the agent's context:
is the container-written `~/.claude/CLAUDE.md` loaded (#245), and do
container-written skills appear in the skill list (ADR-0016). They are
`mode=agent` stanzas, run only with `--agent`, and the `env-conformance` skill
drives them.

**The agent quotes rather than answers yes or no.** "Do you have policy?"
invites a confident yes. Instead the skill asks for the opening words of the
paragraph under a named heading in the policy, and of a named skill's
description in the skill list. The answers are passed in with `--answer`, and
the probe compares them with the deployed file: case and punctuation are
ignored, at least five words are required, and the quote must come from the
first paragraph. Nothing is added to the policy for this, because existing
text works as the sentinel. That matters because the cloud profile is at its
line budget.

**The controls name a heading and a skill that exist nowhere.** The only
honest answer to them is `absent`. An agent that quotes something for one is
answering from expectation, so the probe reports that as `present`, and the
runner calls the whole check `unproven`.

**A session that read the file first cannot take part.** A quote copied from
a file read is not evidence of delivery, so the skill reports such a session
`unknown`, never `pass`.

## Not covered here

- **Skill-body caching.** Is an already-invoked skill's body served from
  cache rather than re-read? Observing it means changing a `SKILL.md`
  mid-session, which breaks the write-nothing rule, so it belongs to the
  scheduled run if anywhere.
- **Scheduled run and filing an issue on mismatch.** That is
  [#655](https://github.com/pmgledhill102/agentic-coding-config/issues/655).

## Baseline

This is the first full run, taken while the suite was being written. A later
failure can be dated against it.

```text
env-conformance 2026-10-20T10:39:55Z
surface=claude-cloud os=ubuntu-24.04 kernel=6.18.44-fc-v139 claude_code=2.1.42 bootstrap_sha=d1588c5b289d3896da40249979b6b772ee4e73fc
mode=full

state=ok pass=19 fail=0 unproven=0 unknown=0 skipped=0
```

Four of the measurements contradict what was recorded earlier. Each is now a
stanza, so the next change gets caught instead of rediscovered:

| Recorded | Measured 2026-10-20 | Stanza |
| --- | --- | --- |
| `gh` absent (#260) | present, and preconfigured for the proxy | `tool-gh` |
| `docs.cloud.google.com` 403 (#241) | reached | `egress-docs-cloud-google` |
| `registry.terraform.io` blocked (#241) | reached (first seen 2026-09-13) | `egress-terraform-registry` |
| `github.com` 403 to curl | reached; release assets download | `egress-github-release-assets` |
