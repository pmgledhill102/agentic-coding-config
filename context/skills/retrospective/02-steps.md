## Steps

The journal entry is written **straight to `journal/` on `paul-context`
`main`** through the GitHub contents API, on every surface: no clone, no
branch, no PR and no draft Issue. Step 1 reads history back the same way. A
`journal-draft` Issue is only the **fallback**, for when that write cannot
happen (step 8).

One store is the point. An entry used to be a draft Issue or a `journal/` file
depending on whether a promotion had run. On a cloud session the promotion
opened a PR, so the entry stayed invisible until a human merged it, and drafts
piled up with nothing prompting a drain. Written directly, an entry is readable the moment it exists
([#453](https://github.com/pmgledhill102/agentic-coding-config/issues/453)).
