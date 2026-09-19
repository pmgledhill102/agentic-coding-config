### 3b. Archived repository (Tier 3 — surface loudly, never act)

From gather section `repo_archived`.

- **`state=false`**: silent. The normal case.
- **`state=unknown`**: silent. Nothing was measured, so there is nothing to
  report — but do not let a later step read it as "not archived" either.
- **`state=true`**: the repo is archived and **read-only on GitHub**. Pushes,
  PR creation, issue creation, comments and label changes all fail; every read
  succeeds, so nothing else in the session notices until the first write.

  That timing is the whole cost. A session can clone, branch, edit, commit,
  lint and pass every local gate, and only learn at the push that none of it
  can be published. So put the marker on the `Repo:` line of the brief and the
  bullet at the **top** of "Needs attention":

  ```text
  Repo:     <repo>  ⚠ ARCHIVED     Branch: <branch> (<clean|dirty>)
  ```

  ```text
  Needs attention:
    • This repo is ARCHIVED — read-only on GitHub. No pushes, no PRs, no new
      issues, no comments. Local commits are possible but cannot be published.
  ```

  Then **stop and ask** before anything else. Do not offer a list of work and
  do not propose a branch: the only useful question is whether this was the
  intended repo, and if it was, what the user wants given nothing can be
  published. Unarchiving is a GitHub settings change and is their call, never
  an action to offer.
