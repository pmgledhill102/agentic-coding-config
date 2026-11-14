# gcp-credentials: replace the 1,700-line shell client with a small Go binary

Status: parked (2026-11-14)
Trigger: The next new feature the `gcp-credentials` client needs: the #236 observer tier, a third tier, or #427 `gcp-run` (the issue's own rule: no new features in the shell client)
From: pmgledhill102/agentic-coding-config#604

## Problem

`home/bin/gcp-credentials` has grown from a script into a client. As of #603 it is 1,697 lines, with 43 functions, 53 `jq` calls and 12 `curl` calls. It is backed by `tests/gcp-credentials-test.sh` (1,030 lines) and `tests/stub-broker.py`, a Python stub broker. What it carries:

- **A state machine.** Pending, grant and token files, now one set per tier.
- **A background refresh daemon.** It runs as `nohup "$0" refresh` and is tracked by pid file.
- **The broker wire contract.** It is spelled as `jq` paths that fail silently when a field is renamed.
- **Two userlands.** It must run under dash (sandboxes) and bash 3.2 (macOS), so every line is written defensively.

The cost was visible in #602/#603. Adding one tier meant threading `--tier` through every subcommand, plus a parallel change in the `gcloud` wrapper in `cloud/bootstrap.sh`, because it has to know which token file and renew arguments match the active configuration.

## Proposal

Port the client to Go as a single static binary with the same command-line surface:

- **Commands unchanged:** `request`, `wait`, `renew`, `refresh`, `status`, `release`, `revoke`, `created`, `teardown`, with the same flags, the same `--tier` behaviour, and the same files under `$CB_HOME`. Existing state stays valid and the skill doc does not change.
- **Typed wire contract:** Go structs for the broker's request, poll, exchange and revoke bodies, mirroring the broker's `CONTRACT.md` (the broker is already Go).
- **Refresh as a subcommand** that daemonises itself, so the `nohup` relaunch goes away.
- **Tests:** Go tests against an `httptest` broker, replacing the shell suite and the Python stub. Port the shell suite's cases as the behaviour spec before deleting it. Its negative proofs (estate configuration not activated, wrapper follows the tier) are what make it trustworthy.
- **`gcloud` wrapper** in `cloud/bootstrap.sh` shrinks to asking the binary which token to use (for example `gcp-credentials token-file`), so tier logic lives in one place.
- **Unchanged invariants:** the access token never passes through stdout, stderr, logs or a shell variable, and is written 0600 straight from the response body.

### The binary carries its own source

The shell client has one property worth keeping deliberately: **any session that has the tool can read exactly what it does.** That matters because the agent running it is the party that has to trust it with credentials. A binary loses that unless it is designed back in. A source copy that can drift from the binary is worse than none, because an agent reads it and trusts it. So:

- **Embedded source.** Use `//go:embed` on the module's `.go` files, `go.mod` and the tests. `gcp-credentials source` lists the embedded files and `gcp-credentials source <file>` prints one. It cannot be missing or out of step with the code that runs, at a cost of a few tens of KB.
- **Unpacked copy for grep and read.** The release archive also carries the source tree, which install unpacks beside the binary (for example `~/.local/share/gcp-credentials/src/`), so agents can `grep` and `Read` it like any other file. The embedded copy is authoritative if the two ever differ.
- **Provenance.** `--version` and `status` print the version and the VCS revision from `runtime/debug.ReadBuildInfo`, which matches a public commit.
- **Reproducible build.** Use a pinned Go toolchain and `-trimpath`, and add `-buildvcs`/`CGO_ENABLED=0`, so anyone can rebuild from that commit and compare hashes.
- **The skill points at it.** `home/commands/gcp-credentials.md` names `gcp-credentials source` as the way to check behaviour, replacing reading the script.

## Decisions needed before building

1. **Where the source lives.** It cannot live in gcp-org-management beside the broker: that repo is private, so a sandbox would need credentials just to download the binary. The options are a Go module inside this repo with its own release workflow, or a small public repo. The client holds no secrets (the request key and broker URL are configuration), so public is fine. It is also required, given the source-carrying design above.
2. **Distribution.** This repo deploys verbatim (a chezmoi archive external), with no build step.
   - **Sandboxes:** the bootstrap currently fetches the helper from raw at a pinned ref (`cloud/bootstrap.sh` around line 703). It would instead fetch a pinned release asset, the same pattern as shellcheck and actionlint. Note that `github.com` 403s the sandbox's curl while release assets resolve.
   - **Workstations:** a chezmoi external of the release archive, or `go install`, which builds from source and so trivially has it.
   - **Platforms:** at least darwin/arm64 and linux/amd64.
3. **Versioning against `CLIENT_VERSION`** (currently 4). The binary reports it the same way, and a release tag carries it.

## When

This is not urgent: the shell client works and is well tested. Proposed rule: **no new features in the shell client**. Whatever next needs the client (the observer grants in #236, a third tier, or #427 `gcp-run`) is the trigger to do this port first.

## Acceptance criteria

- [ ] Source location and distribution decided, recorded as an ADR (it changes what this repo deploys)
- [ ] Go binary with command-line parity; every case in `tests/gcp-credentials-test.sh` ported and passing
- [ ] `gcp-credentials source` prints the embedded source, and a test asserts that the embedded file set matches the module's files, so a new file cannot be left out
- [ ] `--version` and `status` print the VCS revision, and a rebuild at that revision reproduces the release binary's hash
- [ ] Release workflow producing pinned darwin/arm64 and linux/amd64 archives containing the binary and its source
- [ ] Bootstrap and workstation install the binary and unpack the source beside it; the `gcloud` wrapper delegates tier and token selection to it
- [ ] The shell client, its shell tests and `tests/stub-broker.py` removed in the same change, so the two never coexist
- [ ] `docs/runbooks/sandbox-gcp-credentials.md` and `home/commands/gcp-credentials.md` reference the binary and how to read its source

## Related

- #602 / #603: the change that made the cost visible
- #236, #427: likely triggers
- #323: lazy-loading gcloud behind the grant wait, which a Go client would make easier to sequence
