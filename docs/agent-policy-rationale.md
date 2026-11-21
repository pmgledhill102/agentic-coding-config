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

## Preview an irreversible batch, then stop

Before deleting, overwriting or force-pushing over a set of resources, list
exactly what the operation will affect and stop for explicit confirmation.

**This does not contradict the non-interactive-flag rule. The two govern
different actors.** Suppress the tool's prompt: `--quiet` on a delete is
right, because a command waiting on a tty an agent does not have is a hung
session. Surface the agent's preview and wait. "Run it immediately, without
prompting" is an instruction about the tool's interactivity. Reading it as
permission to skip checking what is about to be destroyed is the specific
failure the rule prevents.

**It is not a security boundary, and not an attempt to be un-instructable.**
An operator who looks at the list and says "yes, delete them" gets the
deletion.

**Why a single command on an absolute path gets the same care.** `rm -rf
/dev/null`, as the first clause of a compound line whose purpose was
something else, left a regular file where the device node had been. Every
`2>/dev/null` in the repo went on "working" while silently accumulating
bytes.

## A silent check has to be able to speak

Silence is only evidence once the check is known to be able to report
something. Run it against a case that must produce a hit, then trust the
empty result.

Ask what question the tool actually answered, and not the one you meant:

- an empty `grep` may mean the pattern is wrong
- a 404 body parses as an empty field
- GNU `date -d ""` returns *now* and does not fail
- a version regex can match a prefix inside a longer token, so a filter never
  sees the `-beta1` it was written to exclude

Each of those returns a clean, confident, wrong answer with no error
anywhere.

## Lint before pushing

Run the relevant linter and test suite locally before `git push`, and push
only if everything passes. The reason is cost: a failure found by CI is a
round-trip, and one found locally is a few seconds. Where a repo has the
pre-commit hook installed the hook enforces most of this at commit time; the
rule is what covers a repo, or a clone, without it.

## Pass the non-interactive flag

An agent has no tty. A command that stops to ask something waits forever,
and the symptom is a hung session and not an error, so it reads as the model
being slow.

Examples: `apt-get -y`, `ssh` and `scp` with `-o BatchMode=yes`, and
`gh --yes` where a subcommand offers it.

The rule is about the tool's own prompting. A shell that aliases `rm` to
`rm -i` is a separate and much rarer thing. Check for it with `type rm`
before assuming it, and do not pass `-f` reflexively, because `-f` also
suppresses the errors you wanted to see.

The agent's own preview before a destructive batch is a different matter and
is not suppressed: see
[Preview an irreversible batch, then stop](#preview-an-irreversible-batch-then-stop).
