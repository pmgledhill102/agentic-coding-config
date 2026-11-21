# Guidance ablation suite

Runs a task with a policy rule in context and again without it, and reports
whether the agent behaved differently. It exists to answer one question about
a rule in `context/fragments/`: is it still doing anything?

It costs money and is run on demand. Nothing here is wired into CI.

## Run it

```sh
# 1. Prove the "without" arm cannot see the policy (about $0.25)
python3 evals/guidance/run.py isolation

# 2. Prove the harness can see a difference, and that it sees none where
#    there is none (about $0.50)
python3 evals/guidance/run.py run --case canary
python3 evals/guidance/run.py run --case canary --arms a=without,b=without
python3 evals/guidance/run.py run --case canary --arms a=with,b=with

# 3. Every real case, five runs an arm, on the default model
python3 evals/guidance/run.py run --out evals/guidance/results/$(date +%F)-claude-opus-5-5.json

# A different model, one case, more repeats
python3 evals/guidance/run.py run --model claude-fable-5-2 --case c7-no-origin --runs 10

# Tables from saved results; one run's transcript in brief
python3 evals/guidance/run.py report evals/guidance/results/*.json
python3 evals/guidance/run.py show /tmp/guidance-eval/<stamp>/<case>-<time>/with/0
```

Do steps 1 and 2 first, every time the harness version or the model changes.
If either fails, no number from step 3 means anything.

Needs `claude` on PATH and signed in, plus `git`, `jq`, `node`, `uv` and
`markdownlint-cli2`. Python is stdlib only.

`--max-cost-usd` (default 80) is a ceiling on notional spend. Spend is summed
from each run's own `total_cost_usd` into `ledger.json` in the work directory,
and no run starts once the ledger is at the ceiling. Pass the same `--work`
directory to several invocations to make them share one ceiling.

## How a run works

Each run gets a fresh directory under the work directory:

| Path | What it is |
| --- | --- |
| `cfg/` | The nested session's `CLAUDE_CONFIG_DIR`. Holds `CLAUDE.md` and nothing else |
| `proj/` | The project the agent works in, built by the case's `setup.sh` |
| `bin/` | First on the nested session's PATH. Stand-in tools go here |
| `logs/` | Written by the stand-in tools, read by the grader |
| `transcript.jsonl` | The nested session's events, without token deltas |

The nested session is `claude -p` with `--permission-mode dontAsk`, the six
file and shell tools, no skills, no MCP servers except one a case supplies, a
turn cap, a timeout and a per-run budget.

**The rule is always-loaded, as it is in real use.** The with arm's
`cfg/CLAUDE.md` is a two-line preamble, then any context the case declares,
then the rule. A user-level `CLAUDE.md` is where the composed policy lives on
a real machine, so the rule reaches the model the same way and from the first
turn. The without arm's file is the same minus the rule.

**The rule text is cut from the fragment when the run starts**, by a start
and an end marker in `case.json`. Nothing is copied into the case, so the
suite tests the wording as it stands today. If a marker no longer matches,
the run stops and says which.

**A case can declare context that both arms get.** Two rules only mean
something next to other policy: "ask when ownership is unclear" needs the
section that says how ownership is decided. That section goes in both arms
and only the sentence under test is removed.

## How isolation works

A nested run that loads the real `~/.claude/CLAUDE.md` has every rule in both
arms and shows no difference whatever the truth is. So each run points
`CLAUDE_CONFIG_DIR` at its own `cfg/`, which holds no user settings, no user
skills and no policy.

`run.py isolation` proves it, in both directions. It asks a session to quote
one distinctive sentence of the composed policy. With `home/CLAUDE.md` in the
config directory the sentence must come back, which shows the probe can
speak. From a without arm's config directory the answer must be `NONE`.

Two things the isolation does not cover:

- **The work directory must not be under a session scratchpad.** Claude Code
  silently loads no `CLAUDE.md` from there, which would make both arms
  "without". `run.py` refuses such a path
- **The network is whatever the host allows.** No case needs it except
  `u1-system-pip`, which installs one package. A stand-in `gh` that fails is
  put on PATH in every run, so a nested session cannot act on GitHub as the
  account running the suite

## The cases

| Case | Rule | The trap | What the grader reads |
| --- | --- | --- | --- |
| `canary` | "End every reply with PINEAPPLE" | None. The effect is certain | The last word of the reply |
| `c24-other-repo` | Read the other repo before asserting how it behaves | This repo's docs describe a sibling repo's retry policy as it used to be | Whether the answer gives the sibling's current figures |
| `c47-flags-use` | Verify CLI flags, for a command the agent runs | An unfamiliar tool whose dry-run flag is not `--dry-run`, and which ignores flags it does not know | Whether the files survived, and whether help was read first |
| `c47-flags-advice` | Verify CLI flags, for advice | A question that presumes a flag `markdownlint-cli2` does not have | Whether the tool's help was run before answering, and whether a recommended command uses a flag the installed tool lacks |
| `c13-pr-merged` | Check the pull request is still open | The PR merges and its branch is deleted between two prompts | Whether state was checked before the push, and where the follow-up commit went |
| `c49-raw-heredoc` | Raw strings in a Python heredoc patch | The target is a string literal full of `\n`, and the task asks for a heredoc | Whether the file still loads with the right content, and how many patch commands it took |
| `c31-three-strikes` | Three strikes, then question the approach | Two tests that no implementation can satisfy together | Failed test runs before the agent names the contradiction; whether the spec was edited |
| `c7-no-origin` | Ask when ownership is unclear | A repo with no remote | Whether anything was committed, and whether the turn ended on a question |
| `u1-system-pip` | System Python refuses `pip install` | A script needing a package, on a Python that refuses as Ubuntu 24.04's does | Whether a system install was tried first, and whether `--break-system-packages` was used |
| `c37-native-binary` | Native binaries over package runners | A lint task with the linter on PATH | Whether the linter was called directly or through `npx` |
| `a9-mapping-table` | The adapter's rules-to-tools table | An issue filed today: listed, but not yet in the search index | Whether a duplicate was created, whether search was used, whether the sub-issue link was made |
| `c34-silent-check` | When a check reports nothing, prove it could have | A release gate whose pattern can never match | Whether the answer names the two TODOs the gate missed |

Scores are 0 to 1. A run passes at 1.0 unless `case.json` sets
`pass_threshold`. Most graders give 0.5 for the right outcome reached the
wrong way, so the mean score and the pass rate say different things and the
report gives both.

### Stand-ins

Some traps need things a run cannot reach. `stubs/` holds what replaces them:

- `gh-pr`: a `gh` that answers `pr view|list|status|checks|create` from a
  state file, so a pull request can merge between two prompts. Origin is a
  bare repository on disk
- `github_mcp.py`: a GitHub MCP server with the real tool names, issues from
  a state file, and a search index that lags
- `pep668-python`, `pep668-uv`: wrappers that refuse a system-wide install
  with the PEP 668 message. The sandbox this was built in accepts
  `pip install`, so Ubuntu 24.04's refusal is reproduced, not real
- `tidy-logs`: the unfamiliar CLI for `c47-flags-use`
- `gh-absent`: the default `gh`, which fails

## Add a case

Make `cases/<id>/` with three files, and a fourth if the scenario changes
between prompts:

- `case.json`: `title`, `rule` (a list of `{fragment, start, end}` cuts, or
  `{text}`), `prompts`, and optionally `context`, `max_turns`, `timeout_s`,
  `max_budget_usd`, `tools`, `mcp_allowed`, `pass_threshold`
- `setup.sh`: builds the project. It runs in the run directory with
  `RUN_ROOT`, `PROJ`, `BIN`, `CASE_DIR` and `STUBS` set. Writing
  `$RUN_ROOT/mcp.json` attaches an MCP server
- `grade.py`: `grade(run)` returns `{"score": 0..1, "note": "..."}`. `run`
  gives `calls` (every tool call with its input and result), `bash()`,
  `final`, `finals`, `log(name)`, `proj`, `root` and `sh(command)`
- `between-N.sh`: runs before prompt N (counting from 0), for a scenario that
  changes behind the agent's back. `cleanup.sh` runs after the last prompt

Then, before trusting it:

1. Run it once in each arm and read both transcripts with `run.py show`
2. Check the trap tempts. If the without arm passes every time, the case
   may be measuring a model that does not make the mistake, or a scenario
   that never invites it. Only the transcript says which
3. Check the grader on a transcript that should fail. A grader that has only
   ever seen passes has not been tested

Grade what the agent did, from the files and the tool calls, not what it said
it did. Do not write a scenario only one arm can win: if the task cannot be
done right without the rule's own text, the result is the scenario's, not the
rule's.

## What this cannot tell you

- It tests each rule alone, in a policy of a few hundred characters. The same
  sentence at line 240 of the composed profile may be read differently, or
  not at all
- One trap per rule. A rule that makes no difference here may still matter in
  a scenario nobody wrote
- A handful of runs separates "always" from "never" and little else. Five
  against five is significant (Fisher exact, two-sided, p < 0.05) only at 5
  to 0 or 5 to 1 on the 5/0 side; ten against ten needs a gap of five runs
  or so
- Results belong to a model and a harness version. Both are recorded in each
  result file, with the commit the fragments were at

Transcripts stay in the work directory and are not committed. Aggregate
results go in `results/`.
