## Steps

Journal drafts are filed as `journal-draft` Issues on
`pmgledhill102/paul-context`, on every surface, with no local-tree branch.
Nothing below needs to resolve where that repo is checked out in order to
*write*; only step 1 looks for a tree, and only to read.

That uniformity is the point. The route used to depend on whether a
`paul-context` checkout happened to be at hand, and the preferred arm of that
branch wrote into a gitignored `_incoming/`, so a draft could evaporate with
the container. One route, durable the instant it is created, is worth the one
API call it costs
([#336](https://github.com/pmgledhill102/agentic-coding-config/issues/336)).
