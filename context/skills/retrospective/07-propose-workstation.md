### 5. Propose — at most three

Merge the step-3 levers and step-4 candidates into **at most 3 proposals, ranked by impact**. Every proposal must state all four of:

1. **What it would have changed *this* session** — concretely, pointing at the transcript.
2. **Expected recurrence** — every session, weekly, only in repos like this one.
3. **Tier price under ADR-0018** — which tier the change lands in: **always-loaded** policy (highest, permanent, paid every turn of every session), a **skill description line** (low, but multiplied by skill count), or an **on-invoke skill body** (~zero until used). A removal states the same tier with the sign flipped — what it frees. A proposal that wants the always-loaded tier carries the burden of proof.
4. **Its lever**, from this table — name the cell:

   | Lever | How a change reaches this machine |
   | --- | --- |
   | Installs | Brewfile / dotfiles |
   | Skills | chezmoi (until #142) |
   | Context | fragments → the workstation profile |
   | Permissions/hooks | chezmoi-managed allowlist |
   | Memory | machine-local memory dir |

   A proposal may target the *other* surface — a change that only matters in a
   cloud sandbox is still worth filing from here. Name the lever as "sandbox
   bootstrap" and let the Issue carry the detail; the cells above are for
   pricing what lands on this machine, not a list of what exists.

**A finding that cannot state all four is a journal observation, not a proposal.** Do not weaken a criterion to promote it. Equally, do not pad to three: zero or one well-priced proposal is a better retro than three padded ones, and the cap is a ceiling, not a target.

#### Product findings are a separate kind

The four criteria, the lever table and the cap of three price **changes to how agents work**. A bug in the code the session was working on is not one: it costs no context and pulls no lever, so it can never state a lever, and filing it under the rule above would leave it as a journal observation that no later `start-session` ever surfaces. Route it as a **product finding** instead, with its own short bar:

- **Evidence** — what broke or nearly broke, from the transcript.
- **Impact** — who or what it hurts.
- **Not already filed** — check the subject repo's open issues.

Product findings **do not count against the cap of three**, and the agent-lever bar is unchanged for everything else. A product finding that was found **and fixed inside this session's own PRs** needs no issue; give it one line in the journal under Observations so the record shows what the session uncovered.
