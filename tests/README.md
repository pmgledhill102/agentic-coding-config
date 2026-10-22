# tests

Behavioural tests for the shell payload in `home/bin/`. Repo-meta: nothing
here deploys to `~/.claude/` or reaches a sandbox.

```sh
sh tests/gcp-credentials-test.sh
```

Requires `python3`, `curl` and `jq`. Runs in a few seconds, makes no network
calls beyond loopback, and touches nothing outside its own temporary
directory — in particular it never runs `gcloud`, so a local run cannot
disturb a real gcloud configuration.

## What is covered

`gcp-credentials-test.sh` drives `home/bin/gcp-credentials` against
`stub-broker.py`, a canned-response stand-in for the credential broker. The
helper talks to the broker over HTTP and nothing else, so swapping the broker
is enough to reach every exit path without a Cloud Run service, a Discord bot,
or a human.

Two properties are the reason the file exists:

1. **Every exit code means what the skill doc says it means.** The doc routes
   an agent on these: stop on 3, retry on 7, never retry on 8. An exit code
   that drifts does not produce a wrong number — it produces an agent doing
   the wrong thing with someone's credentials.

2. **No token ever reaches stdout or stderr.** Every byte printed by every
   case is accumulated and searched for a sentinel token at the end of the
   run, so the check covers cases added later without anyone remembering to
   assert it. The request key is checked the same way.

Also asserted: the token and grant files are written 0600, the token file
holds exactly the token with no trailing newline, `X-Client-Version` is sent
on both `/request` and `/poll`, and a 426 during polling leaves the pending
request in place so `wait` can resume it after the helper is updated.

## Adding a case

`canned <endpoint> <status> [body]` sets what the stub returns next;
endpoints are `request`, `poll`, `exchange`, `revoke`. `run <args...>` invokes
the helper and captures both streams. Then assert with `expect_rc`,
`expect_out`, `expect_no_out`, `expect_file` or `expect_no_file`.

Always pass `--no-gcloud --no-refresh` to `request`: the first keeps a local
run from touching a real gcloud configuration, the second stops a detached
refresh loop outliving the test.

`CREDENTIAL_BROKER_REFRESH_INTERVAL` exists so the refresh loop can be
exercised without waiting 45 minutes. Nothing here uses it yet — the loop is
the least covered part of the helper and the obvious next addition.

## Telemetry

`agent-telemetry-test.sh` drives `home/bin/agent-telemetry` and its Claude hook
wrapper against `stub-ingest.py`, a stand-in for the telemetry ingest
(`gcp-org-management` ADR 026). It covers the spool format, the metadata
allowlist, offset advance on 2xx only, `Retry-After`, no auth header when the key
is proxy-injected, an idempotent transcript tail, and the unset-URL case (spool
only, exit 0, no request).

A fake `curl` on `PATH` records every argument the helper passes, which is what
"the key never appears in argv" is checked against: the key and the signed upload
URL both travel in mode-0600 curl config files. Runs in a few seconds, makes no
network calls beyond loopback.

`agent-shim-test.sh` drives `home/bin/agent-shim`, the watched-wait events in the
hook wrapper, and `agent-telemetry session-shape` (#625). It compares every
shimmed call against the bare tool byte for byte (arguments, stdin, stdout,
stderr, exit code), including with the helper absent, broken, or unable to
write; runs a real `git commit` whose pre-commit hook calls a shimmed tool, to
see `via=git-hook`; proves a missing tool is a plain 127 even with a second
route to the shims on `PATH`; and measures the latency a call adds, which must
stay under 10 ms.

## Environment conformance

`env-conformance-test.sh` drives `home/bin/env-conformance` with stubbed `curl`
and `gh` on `PATH` and fixture matrices, so every status (`pass`, `FAIL`,
`unproven`, `unknown`, `not-applicable`, `invalid`) and every exit code is
reached offline. It also validates the real `home/conformance/matrix.conf`
(complete stanzas, controls through their probe's own function, unique ids) and
asserts a full run leaves `HOME` and cwd untouched. The agent probe is driven
with `--answer` against fixture policy and skill files, including a quote
offered for a control that cannot exist, which must read `unproven`. `env-conformance-stamp`, the suite's one writer, is held to
changing only the named stanzas' `measured=` lines, and to writing nothing when
any id is unknown. The runner's real job is in
a sandbox; see `docs/environment-conformance.md`.
