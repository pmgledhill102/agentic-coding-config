# Agent policy: the reasoning behind the short rules

The always-loaded agent policy in `context/fragments/` states each rule as a
short instruction. This document holds what was cut to get there: why the rule
exists, what it guards against, and the examples beyond the one the rule
keeps. Nothing here is needed to follow a rule. Read it when a rule looks
arbitrary, or before changing one.

It was split out under
[#785](https://github.com/pmgledhill102/agentic-coding-config/issues/785),
which found that about half the always-loaded text was reasoning. Two rules
keep their reasoning elsewhere:

- Merge commits only:
  [`home/standards/github-standards.md`](../home/standards/github-standards.md#merge-methods)
- The ephemeral-first principles: [`ephemeral-first.md`](ephemeral-first.md)

## Ownership is read from the origin remote

The signal that says whether a repo is mine is already in every clone, so
nothing has to be declared in the repo and nothing can drift.

Both URL forms are in live use:

```sh
git remote get-url origin
# git@github.com:pmgledhill102/<repo>.git
# https://github.com/pmgledhill102/<repo>.git
```

So a test matches on the `<owner>/<repo>` part and not on a prefix. A rule
written against `https://` alone silently misses every SSH clone, and that
silence reads as "the standards do not apply", not as an error.

## In someone else's repo, their conventions win

A repo that is not mine is a work repo, or a third-party project cloned to
read or contribute to. Its own conventions win on everything: its branch
naming, its commit style, its issue tracker or the absence of one, and its
review norms. Read them before acting.

The specific habit to leave behind is creating issues to "track" work. In my
own repos an issue before work is the convention; in someone else's tracker it
is noise their maintainers did not ask for.

## A read-back of just-written state lags

IAM bindings (inherited grants included), Cloud Logging entries and GitHub's
search index all lag their writes by seconds to minutes. Each reports the lag
as a plausible wrong answer and not as "not ready yet":

- a new IAM binding gives a bare permission denial, indistinguishable from a
  missing role
- a log query gives an empty result
- a search, or a read of something just created, gives nothing or a 404

So when a just-written thing looks absent or unauthorised, wait and retry
once before investigating, and treat "the platform is broken" as the last
hypothesis.

The GitHub instance is issue search, which is why the policy says never to
use it for anything time-sensitive. That rule and its reasoning are in
[`github-issues-workflow.md`](github-issues-workflow.md#rules-for-agents).

This is different from a cached read going stale, which is the pull request
that merged while the session was looking elsewhere. Both produce a
confident wrong assertion; the fix for that one is to read again now.

## A detailed issue is the cross-repo route

Filing an issue in the target repo is encouraged, not a consolation prize for
being unable to edit it. It is the sanctioned route: the change then enters
that repo's issue queue and goes through its review and pull-request flow,
which a cross-repo edit bypasses.

"Detailed" is defined in the rule. The aim behind the definition is that the
fix is a mechanical edit for whoever picks it up, with nothing left to
rediscover.

## Config changes go through an issue

To change agent configuration, open an issue against
`pmgledhill102/agentic-coding-config`. Describe what should change and why,
and add acceptance criteria if they help. The owner works that issue inbox
directly in sessions on this repo, where the source lives.

This is the route from any surface, because whatever config is on disk is
generated: composed from fragments and delivered by chezmoi on a workstation
or by the bootstrap in a sandbox. An edit in place is lost on the next apply.
The issue is the change.
