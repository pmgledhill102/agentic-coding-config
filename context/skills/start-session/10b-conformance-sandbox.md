### 5d. Do the platform behaviours still hold? (Tier 1 — surface, never act)

From gather section `conformance`: the fast subset of the capability matrix
(`~/.claude/conformance/matrix.conf`), probed by `~/.claude/bin/env-conformance`.
Each entry is a platform behaviour a decision here rests on — an egress lane,
a tool in the image, hooks in a container-written `settings.json` firing — and
each one fails silently when the vendor changes it: the session looks normal,
and the first sign is a skill confidently doing the wrong thing.

- **`state=ok`**, **`state=not-applicable`**, **`state=absent`**: silent.
  `not-applicable` is a surface with no matrix entries (Codex); `absent` is a
  container that predates the helper and self-heals on its next rebuild.
- **`state=mismatch`**: one "Needs attention" line per `FAIL` block, carrying
  its `invalidates:` text. That text is the point: it names the skill, script
  or decision that just became false, so say which of them this session is
  about to lean on. A mismatch does not mean the platform is broken — it means
  a recorded measurement is stale — so treat whatever it invalidates as
  unverified for the rest of the session rather than routing around it.
- **`state=unproven`**: a probe and its negative control gave the same answer,
  so the pass means nothing. One line naming the entry; the matrix needs a
  better control.
- **`state=invalid`**: a matrix stanza is malformed. One line; it is a repo
  bug, not platform drift.
- **`state=unknown`**: nothing could be asked, usually no network. Mention it
  once, and only if `fetch` succeeded — otherwise the fetch failure already
  says it.

**Never edit the matrix from here, and never re-run in full mode unasked.** A
mismatch is reported; whether the claim, the matrix or the dependants change is
the human's call, and the full run (and the issue it files) is the scheduled
suite's job (#655).
