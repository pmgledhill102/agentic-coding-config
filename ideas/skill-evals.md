# Nothing measures whether our own skills help, so every subtraction decision is a vibe check

Status: parked (2026-11-14)
Trigger: Telemetry shows a skill is invoked, and whether to keep or retire it is contested (the sequencing proposed in the issue's own comment)
From: pmgledhill102/agentic-coding-config#446

## The gap

We have 20 skills, a composition system, and a test suite that verifies they compose *correctly*. Nothing anywhere measures whether any of them make an agent **better**.

That matters because two standing mechanisms already depend on an answer we do not have:

- **#405** — always-loaded policy is over budget in every composed output. Something has to go. Nothing says what.
- **The `retrospective` skill** prices changes in tiers and treats removals as co-equal with additions. That framing is sound, but the evidence feeding it is one session's impressions.

Both are asking "is this earning its tokens?" and both currently answer by judgement. That is the exact practice Weinmeister's article opens by naming: *"Usually, we answer that with a vibe check: run a couple of prompts in a terminal, see if the output looks decent, and move on."*

## Why this is filed P4

Deliberately. It is real effort, it costs money per run, and its payoff is entirely indirect — it ships nothing, it only makes future subtraction defensible. It belongs in the backlog with an honest price on it rather than near the top with an optimistic one. **If it stays P4 for a year, that is a valid outcome and not a failure of tracking.**

## What exists to build on

- **NVIDIA SkillEvaluator** — [github.com/NVIDIA/SkillEvaluator](https://github.com/NVIDIA/SkillEvaluator) — replays raw execution transcripts against an LLM judge, scoring discoverability, execution efficiency, factual correctness, goal effectiveness, security attribution
- **Harbor** — [github.com/laude-institute/harbor](https://github.com/laude-institute/harbor) — sandbox trial lifecycle, mounting the skill for one arm and omitting it for the other
- **A worked dataset and rubric** — [kweinmeister/scripts/evals/google-cloud-developer](https://github.com/kweinmeister/scripts/tree/main/evals/google-cloud-developer)

And we are unusually well placed to run it: `gcp-org-management` already provisions isolated per-sandbox projects on demand, which is most of the "fair benchmark requires isolation" problem solved.

## Two things that must not be inherited uncritically

**1. The composite score has a floor-effect artefact.** In the published run the efficiency dimension scored exactly `0.0000` for every baseline trial, because the rubric's waste indicators fired at least once in all of them. An agent that explored once scores the same as one that thrashed fifty times. That single dimension contributes `(0.8616 − 0) / 5 ≈ 0.172` of a composite whose reported lift CI is `[+0.28, +0.46]` — roughly **half the headline**. Any rubric we adopt needs a graded efficiency measure, or the number will flatter whatever we test.

Related: Scenario 5 of that run (+0.8298, the largest single lift) asked the agent to *find official Google skills* — a task unwinnable without the skill-catalogue skill. Self-referential scenarios inflate aggregates. Ours must not contain any.

**2. Their rubric and our policy actively disagree.** Scenario 11 scores `gcloud auth application-default login` as the **correct** answer. #440 proposes blocking that command outright, because our credential broker exists to close exactly that path. Running their dataset unmodified would grade our own security policy as a failure. Fork the rubric alongside the scenarios, or the first result will be noise.

## Proposed pilot

Not 72 trials. **18**: 3 scenarios × 3 attempts × 2 arms (with/without skill).

Target the two load-bearing, never-measured candidates:

- **`start-session`** — runs at the top of nearly every session; expensive if it is not paying
- **the `setup-*` family** — 15 skills held out of the sandbox whitelist deliberately; if they cannot be shown to help, that is an argument for retiring some, which is the kind of finding #405 needs

Scenarios must be things an agent gets *wrong* without the skill and *right* with it. If a scenario passes in both arms it measures nothing; if it fails in both, the skill is not the variable.

## Kill criteria — state these before starting

- If the pilot cannot produce a scenario where the arms diverge, **stop**. That is itself the finding: the skill is not doing measurable work, and 18 trials was a cheap way to learn it.
- If per-run cost exceeds the value of the decision it informs, stop. A £50 experiment to justify deleting 40 lines of policy is not a good trade.
- If building the harness exceeds ~2 sessions before producing a single scored trial, stop and write up what blocked it.

## Acceptance criteria

- [ ] A decision recorded on whether to run this at all, with the cost estimate that informed it
- [ ] If yes: 18 trials completed, transcripts retained, scores published into the repo (not a chat summary)
- [ ] The rubric used is ours — graded efficiency, no self-referential scenarios, no conflict with #440's credential policy
- [ ] At least one concrete disposition on a real skill: keep, amend, or retire, with the trial data cited
- [ ] Result linked from #405, whichever way it goes

## Related

- #405 (the decision this exists to inform), #440 (the rubric conflict), #444 / #445 (rules from the same source that need no measurement to adopt)
- Source: [Do Agent Skills Help? I ran 72 trials to find out](https://medium.com/google-cloud/do-agent-skills-help-i-ran-72-trials-to-find-out-b328ba4d66b2)
