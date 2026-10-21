# Scheduled environment conformance run

The weekly run that re-measures the capability matrix and files an issue when
a platform behaviour has moved
([#655](https://github.com/pmgledhill102/agentic-coding-config/issues/655),
part of [#260](https://github.com/pmgledhill102/agentic-coding-config/issues/260)).
The procedure lives in the `env-conformance` skill, step 5. This page holds
what is outside the repo: the scheduled task's settings and its exact prompt,
so the task can be recreated from here rather than from memory.

## The scheduled task

| Setting | Value | Why |
| --- | --- | --- |
| Name | `Weekly environment conformance` | |
| Schedule | `CRON_TZ=Europe/London 51 7 * * 1` (Mondays 07:51 UK) | Weekly matches the snapshot cache's roughly 7-day expiry, so most runs see a freshly built container. 07:51 avoids the on-the-hour scheduling queue. |
| Session | a fresh session per run | Step 1 of the skill is evidence only in a session that has read nothing. A resumed session has always read something. |
| Environment | the `agentic-coding-config` cloud environment, the one whose setup script runs `cloud/bootstrap.sh --with-hooks` | The run tests what that bootstrap delivers. A bare environment fails every agent check, correctly but uselessly. |
| Connectors | none beyond the session's own GitHub access | It files issues and opens one PR, both on this repo. |
| Notifications | push and email | A run that filed an issue is the one worth hearing about. |

## The prompt

Copy this verbatim. The first sentence is load-bearing: it has to come before
anything else the session does.

```text
As your very first action, before reading any file, running any command or looking at the repository, invoke the env-conformance skill with the argument `scheduled` (that is, /env-conformance scheduled) and follow it to the end. Its first step only counts as evidence in a session that has not read anything yet.

If env-conformance is not in your skill list, that absence is the finding. In pmgledhill102/agentic-coding-config, list the open issues (never search them). Comment on the open issue titled "Conformance drift: agent-skills-listed", or create it with labels P1 and "type: bug" as a sub-issue of #260, saying the skill was not listed in a fresh scheduled session and naming the session. Then stop.

Work only in pmgledhill102/agentic-coding-config. Never merge a pull request. Finish with the skill's step 5d summary.
```

## Operating it

- **Test-fire it** after creating or changing it, with the "fire now" action
  on the scheduled task. Then read the session it started. A healthy run
  ends with a step 5d summary and a new comment on #260.
- **Pause it** by disabling the scheduled task rather than deleting it.
  Deleting it loses its run history and every session it started.
- **Change the prompt here first**, merge, then update the scheduled task
  from the merged text. A task whose prompt differs from this page is one
  nobody can recreate.

## What a run produces

| Outcome | Where it shows |
| --- | --- |
| Every run | One comment on #260 with the environment header and both `state=` lines |
| A `FAIL`, `unproven` or `invalid` entry | One open issue per entry id, titled by status. A repeat on a later run comments on that issue rather than filing again |
| The first clean run in a calendar month | One PR, `Conformance: refresh measured= dates (<YYYY-MM>)`, changing only `measured=` lines. A human merges it |
