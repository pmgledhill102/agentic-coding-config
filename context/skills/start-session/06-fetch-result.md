### 2. Surface fetch result (Tier 1)

Folded into step 1's gather. On success, the `fetch` section is empty (exit=0, no body) — silent pass. If its exit code is non-zero, the body contains the error output; halt the rest of the phase and surface it — every downstream step assumes a successful fetch.
