## Steps

**First, resolve the `paul-context` tree.** Steps 1 and 8 both need it, so work it
out once here and refer to it as `<pc>` throughout. Take the first rule that
hits:

1. **The checkout you are standing in.** If `basename "$(git rev-parse --show-toplevel)"` is `paul-context`, that is the tree — wherever it sits on disk.
2. **The conventional location.** Else, if `~/dev/paul-context` is a directory, that is the tree.
3. **No local tree.** Else `<pc>` is unset, and every step that would have used it takes its Issue route instead.

**Never name `~/dev/paul-context` outside rule 2.** It is one machine's layout,
not a property of the repo — the delivery assumption ADR-0016 principle 3 and
ADR-0018 principle 6 both forbid in portable text. A cloud session working on
`paul-context` has it checked out at `/home/user/paul-context`; hardcoding the
`~/dev` spelling is what filed four journal drafts as Issues while their
destination sat in the working directory
([#286](https://github.com/pmgledhill102/agentic-coding-config/issues/286)).

Rule 3 is a real answer rather than a failure — it is correct whenever this
retro runs in some other repo, which is most of the time. What rule 1 fixes is
the case where the tree is *right there* and the skill could not see it.
