# GitHub repository standards — moved

This document now lives at
[`../home/standards/github-standards.md`](../home/standards/github-standards.md).

It moved so that **every surface has a local copy**. `home/standards/` is
carried to a workstation by chezmoi and to a cloud sandbox by
`cloud/bootstrap.sh`, landing at `~/.claude/standards/` on both. A document
under `docs/` reaches neither, so anything wanting the standard had to fetch it
over the network at the moment it was needed — and a failed fetch is
indistinguishable from a standard that says nothing.

This stub is deliberate rather than tidy: the old path is linked from issues
and commit messages in `paul-context` and elsewhere, and those links should
keep resolving.
