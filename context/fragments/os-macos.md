# macOS

True only on **macOS**: BSD userland, zsh as the interactive shell, `/bin/sh`
is bash in POSIX mode. What other operating systems receive, and at what
support tier, is [ADR-0020](https://github.com/pmgledhill102/agentic-coding-config/blob/main/adrs/0020-surface-matrix.md).

## The interactive shell is zsh

Three differences from bash bite silently, which is why loops belong in a
script file run with `sh` or `bash` rather than composed inline:

- **No word-splitting on unquoted variables.** `set -- $TWO_WORDS` splits
  into two arguments in bash and stays one argument in zsh, so the loop runs
  once with a joined value and downstream parsing fails somewhere unrelated.
  zsh needs `${=VAR}` or a real array
- **`:` is a modifier.** `"$MODEL:generateContent"` flirts with zsh's
  `:g`-style parameter-modifier parsing; write `${MODEL}:generateContent`.
  A bare `$VAR:` in a URL is a trap
- **`ls` here is eza, which prints nothing when piped.** `ls -a1 | grep …`
  yields an empty stream rather than an error, so an empty listing reads as a
  deleted working tree. Parse `find . -maxdepth 1`, `/bin/ls` or `git ls-files`
  instead; bare `ls` for human eyes is fine

Empty arrays also behave differently in zsh under `set -u`.

## Local scratch space

`/tmp` on macOS is per-user and ephemeral, and is the standard place for
staging multi-line content (issue bodies, PR bodies) before passing it to a
tool via `--body-file`. Note that macOS resolves `/tmp` to `/private/tmp`,
which is why permission rules carry both spellings.

**Do NOT use heredocs (`cat <<'EOF'`) or ANSI-C quoting (`$'...\n...'`) in
shell commands here.** A heredoc is a multi-line command, so it matches no
prefix-matched `Bash(...)` rule and prompts every time however ordinary it
is; ANSI-C quoting also gets flagged for hiding characters. Stage the
content in `/tmp` and pass it with `--body-file`, or use a surgical edit
tool — `Edit(/tmp/**)` is auto-approved to make that path free.
