### 14b. Armed check-in triggers (Tier 3 — surface only, never delete)

From step 1(c). A self-check-in scheduled mid-session outlives the work it was
watching: one session opened three PRs, armed hourly check-ins, and finished
leaving one armed for 06:35 naming two PRs that had already merged. Nothing in
this skill looked, so it was caught only because the agent happened to run the
listing off its own initiative
([#279](https://github.com/pmgledhill102/agentic-coding-config/issues/279)).

- **`triggers-unavailable`** — the summary line reads `n/a (not checked)`, said
  once. Never "none": an unchecked list must not render as clean, the same rule
  the GitHub sections follow.
- **None armed** — silent. The normal case.
- **One or more** — list each with its `next_run_at` and enough of its `prompt`
  to identify the subject, then stop. Deletion is the user's call: a trigger may
  be deliberate, and a single y/n cannot carry per-item judgement across
  triggers pointing at different work.

**Call out the ones whose subject has already finished.** Where a trigger's
prompt names a PR that step 8's open-PR list does not contain, say so — that is
the actionable case, and the one #279 was filed from. It reads prompt text
rather than resolving a reference, so offer it as "looks already merged or
closed" rather than as fact.

**Only this session's.** `list_triggers` is account-wide, so an unfiltered list
shows other sessions' live work. Reporting that as leftover mess is a false
positive, and acting on it would be worse — a sibling session watching its own
PR is doing its job. Step 1(c) filters on `persistent_session_id`.

Worth knowing before deciding anything is urgent: a trigger whose session is
gone fires once, fails to bind, and disables itself
(`ended_reason=auto_disabled_session_gone`), so an abandoned trigger costs one
failed fire rather than a recurring wakeup. The case that still costs is a
**live** session walking away with triggers armed — which is the session
running this skill, which is why the check belongs here rather than in a sweep.
