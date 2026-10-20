---
name: env-conformance
description: 'Check that the platform behaviours this repo relies on still hold in this sandbox: run the capability-matrix probes, then answer the checks only the agent can make (is the composed policy in context, are the delivered skills listed), each with a negative control. Use when asked to check conformance, verify the environment, or test for platform drift.'
---

# Environment conformance

Some claims about the platform can only be checked from inside the agent's
own context. Is the container-written policy file loaded? Do
container-written skills appear in the skill list? A script cannot see your
context, so for these you report what you see and
`~/.claude/bin/env-conformance` checks it against the files on disk. The
design and the status meanings are in `docs/environment-conformance.md` in
`agentic-coding-config`.

## 1. Answer from context first, before reading any file

**Do these four before running any command or reading any file.** Answer
from what is already in your context: the system prompt, loaded policy and
the skill list. Do not use what a file read could tell you. Reading the file
first turns an observation into a copy, and the copy always passes.

**If this session has already read `~/.claude/CLAUDE.md`, a
`context/fragments/` file, or `~/.claude/skills/end-session/SKILL.md`, stop
here.** Report the agent checks as `unknown (context contaminated by a file
read)` and go to step 3. A verbatim quote is only evidence when it could not
have come from somewhere else.

Write down each answer exactly. Use the literal word `absent` when you
cannot see the thing. Never reconstruct or guess.

1. **`policy`**: in your loaded policy, find the heading **This container is
   the whole environment**. Quote the first eight or more words of the
   paragraph under it.
2. **`policy-control`**: the same for the heading **Conformance control
   heading**.
3. **`skill`**: in your list of available skills, find **`end-session`**.
   Quote the first eight or more words of its description.
4. **`skill-control`**: the same for the skill
   **`conformance-no-such-skill`**.

Items 2 and 4 are the negative controls. Neither exists anywhere, so the
right answer to both is `absent`. If you find yourself quoting text for
either, every answer from this step is suspect. Give your answers as you
have them anyway: the runner marks the check `unproven`, which is the
honest result.

## 2. Hand the answers to the runner

Put each answer in single quotes. If one contains a `'`, replace it with a
space; punctuation is ignored when comparing.

```sh
~/.claude/bin/env-conformance --agent --answer 'policy=<answer 1>' --answer 'policy-control=<answer 2>' --answer 'skill=<answer 3>' --answer 'skill-control=<answer 4>'
```

## 3. Run the script-checkable probes

```sh
~/.claude/bin/env-conformance
```

This is the full mode: every non-agent entry. It takes about 6 seconds and
only reads. Expect a few lines of proxy chatter about refused connections:
those are the negative controls, aimed at hosts that must be blocked.

## 4. Report

Give one summary that combines both runs:

- The `state=` line of each run.
- Every `FAIL`, quoted with its `invalidates:` line. That line names the
  decision, script or skill that is now unproven. Say which of them the
  current task relies on.
- Every `unproven` or `invalid` entry, and what it means for this run.
- The environment header line (date, os, CLI version, bootstrap sha), so the
  result can be dated.

On this surface, `unknown` and `not-applicable` are not failures. Say what
went unchecked and stop there.

## Guardrails

- **Never edit the matrix, the runner or the deployed files to make a check
  pass.** A FAIL means a recorded measurement no longer holds. Whether the
  claim, the matrix or what depends on it changes is for a human to decide.
  If the user asks for follow-up, file it as an issue on
  `pmgledhill102/agentic-coding-config` naming the failing entry ids.
- **Never retry step 1 after seeing a result.** A second answer, given
  after the runner said the first was wrong, is no longer an observation.
- On a workstation, or any surface other than a Claude cloud sandbox, both
  runs report `not-applicable`, because the matrix records sandbox behaviour
  only. Report that and stop.
