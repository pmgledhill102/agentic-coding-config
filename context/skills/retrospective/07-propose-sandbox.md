### 5. Propose — at most three

Merge the step-3 levers and step-4 candidates into **at most 3 proposals, ranked by impact**. Every proposal must state all four of:

1. **What it would have changed *this* session** — concretely, pointing at the transcript.
2. **Expected recurrence** — every session, weekly, only in repos like this one.
3. **Tier price under ADR-0018** — which tier the change lands in: **always-loaded** policy (highest, permanent, paid every turn of every session), a **skill description line** (low, but multiplied by skill count), or an **on-invoke skill body** (~zero until used). A removal states the same tier with the sign flipped — what it frees. A proposal that wants the always-loaded tier carries the burden of proof.
4. **Its lever**, from this table — name the cell:

   | Lever | How a change reaches a container like this one |
   | --- | --- |
   | Installs | bootstrap flags (`--with-gcloud/-precommit/-hooks`), setup script, egress allowlist |
   | Skills | bootstrap `SKILLS` / `COMPOSED_SKILLS` whitelist |
   | Context | fragments → the cloud-sandbox profile |
   | Permissions/hooks | bootstrap-written `settings.json` |
   | Memory | **none — memory writes die with the container** (see step 6) |

   Note what the memory row costs you: a lesson worth keeping has no
   machine-local home here, so it has to leave the container as a journal
   entry or an Issue or it is gone. That is not a limitation to work around —
   it is why the durable-lesson route in step 6 is what it is.

   A proposal may target the *other* surface — a change that only matters on a
   workstation is still worth filing from here. Name the lever as "chezmoi /
   dotfiles" and let the Issue carry the detail; the cells above are for
   pricing what lands in a container, not a list of what exists.

**A finding that cannot state all four is a journal observation, not a proposal.** Do not weaken a criterion to promote it. Equally, do not pad to three: zero or one well-priced proposal is a better retro than three padded ones, and the cap is a ceiling, not a target.
