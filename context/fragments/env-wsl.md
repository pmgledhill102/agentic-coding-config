# WSL

True only on **WSL2 on a personal Windows workstation**: an Ubuntu distro
whose Windows host is mounted under `/mnt/<drive>`. Composed after the
Ubuntu and durable-machine fragments, so the userland and the chezmoi
mechanics are as they state; this section is only what being inside Windows
adds. Treat the machine as native Ubuntu.

## Stay on the Linux filesystem

`/mnt/c`, and any other `/mnt/<drive>`, is the Windows host. Its own clones
live there, worked on by Windows tools.

- **Work under `~/dev`**, on the distro's ext4. A repo is never shared
  between Windows and WSL; each side has its own clone
- **Never clone, edit, commit or build under `/mnt/<drive>`.** Read a
  specific path there only when the user points at it
- **Never invoke Windows binaries** (`*.exe`, `powershell.exe`,
  `cmd.exe`). They are kept off `PATH` deliberately; interop stays enabled
  only for browser-based auth and `code`
- **Credentials stay on this side.** `gh auth login` inside WSL, and its
  own SSH key; never bridge to the Windows Git Credential Manager

Why: the mount is 9P, slow for git and anything that walks a tree; line
endings and permission bits differ per side; and two agents on one clone
from two operating systems collide where neither can see it.

A session that starts with its working directory under `/mnt/<drive>` is
told so by a `SessionStart` hook. Ask the user before doing anything there.

## The interactive shell is zsh

Loops belong in a script file run with `sh` or `bash`, not composed inline.
zsh does not word-split an unquoted variable, so `set -- $TWO_WORDS` stays
one argument (use `${=VAR}` or an array), and `$VAR:` reads as a modifier
(write `${VAR}:`). To list a directory for parsing, use `find . -maxdepth 1`
or `git ls-files` rather than `ls`, whose output depends on aliases.

## Local scratch space

`/tmp` is plain `/tmp` on ext4, and is where multi-line content (issue
bodies, PR bodies) is staged before passing it with `--body-file`.

**Do NOT use heredocs (`cat <<'EOF'`) or ANSI-C quoting (`$'...\n...'`) in
shell commands here.** A heredoc is a multi-line command, so it matches no
prefix-matched `Bash(...)` rule and prompts every time; ANSI-C quoting is
flagged for hiding characters. Stage the content in `/tmp`, or use a
surgical edit tool — `Edit(/tmp/**)` is auto-approved to make that path free.
