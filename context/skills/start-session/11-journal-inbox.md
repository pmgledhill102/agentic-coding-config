### 6. Paul-context inbox surface (Tier 2 — prompt, paul-context only)

**Only fires when the current working tree is `paul-context`** (`basename "$(git rev-parse --show-toplevel)" = "paul-context"`). Otherwise skip silently. This is a runtime filesystem check, not part of the gather output — `start-session` runs in many repos and a generic gather section would always be empty for the rest.

```sh
ls -1 _incoming/ 2>/dev/null
```

Filter the listing to entries matching `^[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9-]+\.md$` (excludes `README.md` and any non-conforming files). Count the matches.

- **0 matches**: skip silently.
- **>= 1 match**: print the count and (up to first 5) filenames, then:

  - **Otherwise (default)**: prompt:

    > `<N>` journal draft(s) pending in `_incoming/`. Run `/promote-journal-inbox` now? (y/n)

    - **yes** → invoke `/promote-journal-inbox` directly. That command's pre-flight verifies cwd, then drains both filesystem `_incoming/` and `journal-draft`-labeled Issues from `pmgledhill102/paul-context`, commits each draft separately, single-pushes, and closes the drained Issues. Carry the result into the session brief.
    - **no / empty / cancel** → carry on. Surface the count in the session brief under "Needs attention" so it's visible at a glance.

Note: this surface only counts the **filesystem** half of the inbox. The Issue-side half (sandbox-fallback drafts) isn't enumerated here — surfacing it would require an extra issue-listing call filtered to the `journal-draft` label, and the filesystem count is the dominant signal because that is where drafts normally land. `/promote-journal-inbox` itself drains both inboxes when invoked, so user action is consistent regardless of which path filed the draft.
