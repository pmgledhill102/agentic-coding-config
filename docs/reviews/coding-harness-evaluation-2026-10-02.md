# Cloud coding harness: requirements, and how the offerings compare

- **Date**: 2026-10-02
- **Inputs**: [`docs/cloud-sandbox-design.md`](../cloud-sandbox-design.md),
  [`cloud/README.md`](../../cloud/README.md),
  [strategic review](strategic-review-2026-08-09.md), ADR-0016, ADR-0017,
  ADR-0018, and the explorations in `pmgledhill102/cloud-playground`
- **Method**: requirements are taken from what those documents say the work
  has needed. Vendor capabilities were researched on the date above, and §5
  says how far to trust each source.

## 1. Verdict up front

**Claude Code on the web is the only offering that meets every must-have
today.** What tips it is three capabilities, used together, that no rival
documents:

- secrets injected by the egress proxy per host, so the key never enters the
  container;
- one network allowlist shared by setup and agent phases, which the broker's
  `POST` flow depends on;
- the agent scheduling its own check-ins, as when a teardown has to wait out
  a 90-minute subnet release.

Its real gaps are:

- **No native cloud identity.** There is no OIDC or workload identity
  federation, which is why the credential broker exists.
- **The agent acts as you on GitHub.** That is ADR-0017's unsolved problem.
- **Claude models only.**
- **Features depend on the plan.** API credentials are Pro/Max only; the
  self-hosted runner pool is Team/Enterprise only.

**Worth exploring, in order:**

1. **Cursor Cloud Agents.** The closest all-round rival. It has documented
   OIDC to GCP Workload Identity Federation, hourly-refreshed environment
   builds, timer and PR-event wake-ups, a phone app and multiple model
   providers. Its gap is secrets, which are still env vars inside the
   container.
2. **Build your own on GCP**: Claude Managed Agents or the Agent SDK, on GKE
   Agent Sandbox or Cloud Run. This is the only path to native workload
   identity in *your* project with *your* egress policy, and Managed Agents
   vaults swap secrets in at egress. It costs engineering, and it suits a
   `cloud-playground` exploration well.
3. **GitHub Copilot cloud agent.** Worth a narrow trial. It runs as a separate
   bot identity, which is the thing ADR-0017 wants. It is multi-model
   (Claude included) and gets OIDC through Actions. But it has a hard
   59-minute session cap, and its config must be committed to each repo,
   which contradicts ADR-0016 principle 1.

**Not worth exploring now:**

- **Devin.** Strong on paper (OIDC to GCP, Outposts), but phone support is
  weak and the price model is heavier. Watch it.
- **Codex.** Already run here (2026-08-13). Its structural gaps remain:
  secrets are stripped before the agent phase, agent network is off by
  default, and hooks don't run in the cloud.
- **Jules, Ona, Factory, Amp.** Each lacks a must-have, or its docs say too
  little to judge. Amp is the one to watch, for self-scheduled wake-ups.

## 2. The requirements

Each requirement is grounded in something the work has already needed.
**Must** means the current way of working breaks without it. **Should** means
a known cost or workaround exists today. **Nice** is an upgrade.

### Must

| ID | Requirement | Why — where it came from |
| --- | --- | --- |
| **R1** | **Async cloud sessions that survive disconnects and can be started and steered from a phone** | Strategic review §2a: about 3 h/week on trains, where a session that loses the signal is useless |
| **R2** | **Environment bootstrap.** A setup script that can fetch a pinned external bootstrap, about 5 min or more of budget, a cached filesystem snapshot, re-runnable mid-session, and some signal when the container is stale | `cloud/bootstrap.sh`, Tier 1/Tier 2 split, `.bootstrap-manifest`, design doc §2 |
| **R3** | **Secret injection outside the sandbox.** The proxy attaches a header per host, so the key can't be read with `env` or `cat` | Developer Knowledge key; broker request key in `proxy-injected` mode |
| **R4** | **Short-lived cloud credentials.** Either a human-approved broker (needs `POST` egress in the agent phase) or native OIDC/WIF. Tokens never pass through argv or the transcript | `gcp-credentials` broker, runbook, cloud-playground lifecycle step 2 |
| **R5** | **Egress control.** A custom domain allowlist that applies to setup and agent phases alike, allows `POST`, and can change live | Design doc §4; Codex's GET-only filter blocked the broker |
| **R6** | **Portable config honoured in the cloud**: AGENTS.md, SKILL.md, harness hooks (`PreToolUse`, `SessionStart`, `Stop`), user-scope MCP, all installable *by the bootstrap* rather than committed to each repo | ADR-0014, ADR-0016 principle 1, ADR-0018 profiles |
| **R7** | **GitHub loop.** Opens PRs, wakes on CI failures and review comments and pushes fixes, works across repos, with repo-scoped access | PR-driving rules, multi-repo sessions (this one has two) |
| **R8** | **Self-scheduled wake-ups and routines.** "Check back in 60 min and finish the teardown" | cloud-playground step 9 (Direct VPC egress holds IPs for 45–90 min); end-session armed triggers |

### Should

| ID | Requirement | Why |
| --- | --- | --- |
| **R9** | **A separate agent identity on GitHub**, so rulesets and audit logs can tell agent from human | ADR-0017: cloud sessions authenticate as the connecting user |
| **R10** | **Sufficient machine and tooling**: about 30 GB disk, Docker or a container build path, gcloud and Terraform installable | Design doc §3 disk table; explorations use Cloud Build because there's no local Docker daemon |
| **R11** | **Telemetry**: OTel export from cloud sessions, and some visibility into the setup phase | Design doc §6, gcp-org-management#630 |
| **R12** | **Parallelism**: several sessions, plus subagents within one | Strategic review §2a |
| **R13** | **Docs and knowledge access**: MCP connectors, Developer Knowledge, golden-source fetching | cloud-playground golden-sources rule |

### Nice

| ID | Requirement | Why |
| --- | --- | --- |
| **R14** | Choice of model provider | Portability is the point of this repo (ADR-0014) |
| **R15** | Run the sandbox in your own GCP project, with native workload identity | Would remove the broker for some flows, and make egress your own policy |
| **R16** | Predictable cost on a personal plan | Personal estate, not an enterprise budget |

## 3. The comparison

● = documented and fits. ◐ = partial, or needs a workaround. ○ = absent or
counter to the requirement. ? = not documented.

| | Claude Code web | Cursor Cloud | Copilot cloud agent | Codex cloud | Devin | DIY: Managed Agents / SDK on GKE or Cloud Run |
| --- | --- | --- | --- | --- | --- | --- |
| **R1** phone + disconnect | ● | ● iOS + PWA | ● GitHub Mobile | ● ChatGPT app | ◐ web/Slack, iOS waitlist | ○ you build it (Managed Agents has SSE events) |
| **R2** bootstrap + cache | ● 5 min, snapshot ~7 d, re-run live | ● Dockerfile / `environment.json`, Builds refresh hourly | ◐ Actions steps, `snapshot` image, but setup shares the 59-min cap | ◐ 12 h cache; setup runs in a separate shell, so exports are lost | ● blueprints, ~24 h snapshot | ● your images; Pod Snapshots (GKE) |
| **R3** proxy-side secrets | ● API credentials (**Pro/Max only**) | ◐ redacted, but env vars | ○ env vars, masked | ○ secrets removed after setup | ◐ env vars, scrubbed from snapshot | ● Managed Agents vaults swap at egress (not self-hosted) |
| **R4** cloud creds | ◐ broker works; no OIDC | ● OIDC → GCP WIF | ● OIDC via `id-token` in setup | ◐ broker needs agent internet on; OIDC unverified | ● `setup-gcp-oidc` | ● native WIF (GKE) / service identity (Cloud Run) |
| **R5** egress | ● one allowlist, both phases, live | ● three modes, per environment | ◐ firewall covers agent Bash only; setup unfirewalled | ◐ agent off by default; GET-only option | ● security profiles | ● default-deny NetworkPolicy / VPC |
| **R6** portable config | ● skills, hooks and CLAUDE.md all land from the bootstrap (measured) | ◐ repo hooks run; user hooks are **not** loaded; `sessionStart` deferred | ◐ hooks and skills, but **repo-committed** only | ◐ AGENTS.md and skills yes; **hooks no** in cloud | ◐ AGENTS.md and skills; cloud hooks ? | ● whatever you install |
| **R7** GitHub loop | ● autofix, CI and review events, multi-repo; no merge-conflict webhook | ● multi-repo, CI and comments | ● native, but one repo per run | ◐ PR triggers (Aug 2026), ≤4 repos | ● auto-fix | ○ you build it |
| **R8** self wake-ups | ● `send_later` / routines (1 h min cron) | ● timers + event subscriptions (Aug 2026) | ○ automations only; 59-min cap | ○ schedules and events only | ◐ one-time automations; sleep/wake | ◐ Managed Agents scheduled deployments |
| **R9** agent identity | ○ acts as you | ◐ GitHub App | ● Copilot bot | ● connector bot | ● bot by default | ● your own App |
| **R10** machine | ◐ 4 vCPU / 16 GB / 30 GB; Docker CLI present, no daemon | ◐ Docker yes, no kind/k3s; size unpublished | ● Actions runner, larger runners | ? | ● Docker; adjustable size | ● your choice |
| **R11** telemetry | ● OTel (measured here) | ◐ OTel on Enterprise only | ◐ metrics API, hooks | ○ cloud OTel ? | ◐ audit logs | ● yours |
| **R12** parallelism | ● | ● up to 20 subagent VMs | ● | ● | ◐ 10 concurrent | ● |
| **R13** knowledge / MCP | ● connectors + user-scope MCP | ● | ● | ◐ local MCP may be unavailable | ● | ● |
| **R14** models | ○ Claude only | ● multi | ● multi, Claude included | ○ OpenAI only | ● picker | ◐ per SDK |
| **R15** own GCP project | ◐ self-hosted pool: Team/Ent beta, no API credentials | ◐ self-hosted workers | ● self-hosted runners (firewall off) | ○ | ● Outposts | ● |
| **R16** personal cost | ● plan limits, no compute charge | ● API price, no VM charge | ◐ Actions minutes + AI credits | ● plan | ◐ $20–$200 + ACUs | ◐ tokens + $0.08/session-h, plus GCP |

### Not tabulated, and why

| Offering | Why it's out for now |
| --- | --- |
| **Google Jules** | Setup script and snapshot, env vars, fixed MCP catalogue. Allowlist, hooks, credentials and lifetime are all undocumented. Fails R3, R5 and R6 as far as the docs show |
| **Gemini Managed Agents** | An API building block, not a harness. Notably it **does** document proxy-side secret injection per domain, plus hooks and remote MCP. Weigh it alongside the DIY column if you build |
| **Ona (ex-Gitpod)** | Devcontainers, OIDC to GCP, a GCP runner Terraformed into your VPC, PR-event automations. Enterprise-shaped, with no phone support documented (R1) |
| **Factory Droids** | Cloud templates and BYO VMs; most rows undocumented |
| **Amp orbs** | **The agent schedules its own wake-ups**, event-driven orbs, phone steering, per-minute sizes. Credentials, egress and hooks are undocumented. **Watch this one** |

## 4. What to explore, as experiments

Each experiment is shaped like a `cloud-playground` exploration: a question,
a control, a verdict.

1. **Cursor: does R4 via OIDC actually replace the broker?** Create a WIF
   pool trusting `https://api.cursor.com`, map one Cursor environment to a
   sandbox SA, and mint a token. Control: a second environment not mapped,
   which must fail. Then port `bootstrap.sh` to `environment.json` `install`
   and see which of R6 survives without user-level hooks.
2. **DIY: Claude Managed Agents with a self-hosted sandbox on GKE Agent
   Sandbox, or the Agent SDK on Cloud Run.** Prove native WIF from inside the
   sandbox, default-deny egress, and vault secret substitution. Measure cold
   start with Pod Snapshots. This is also the only route to a session that
   is genuinely yours end to end.
3. **Copilot: is a bot identity worth a 59-minute cap?** Run one
   PR-maintenance chore (dependency bump plus CI fix) as the Copilot bot
   with a ruleset that blocks your own user from bypassing review. That
   tests ADR-0017's preferred option for free.
4. **Claude, closing its own gaps:** test whether a ccpool runner's session
   JWT can be exchanged at the broker. The broker would then be the "token
   service" the docs call for, and the human-approval card stays. Separately,
   re-measure the setup budget against the 5-minute snapshot threshold.

**One caution on OIDC.** Native federation removes the broker's **human
approval card**, which is a control you chose deliberately (runbook: "the
broker's job is to make token theft boring"). WIF from a vendor's issuer
means any session in that environment gets the role with no approval. If
you adopt it, scope it to sandbox projects only, or keep the broker in front
and federate the broker instead.

## 5. Confidence

- **Claude Code**: high. Docs were read verbatim from `code.claude.com`, and
  the container facts (CPU, RAM, Docker CLI with no daemon, OTel, hooks) were
  observed in this session or in earlier measured runs.
- **Copilot**: high. Read from the `github/docs` source on 2026-10-02.
- **Cursor, Codex, Devin, Jules, Ona, Factory, Amp, Google**: medium to low.
  This sandbox's egress proxy blocks those vendors' doc sites, so the facts
  come from search summaries of the official pages. Treat them as leads, per
  the cloud-playground golden-source rule, and confirm before acting.
  Specific rows to re-check:
  - Codex OIDC;
  - Cursor's concurrency limit and the deferral of `sessionStart`;
  - Devin's OIDC and Outposts dates;
  - every "?" in the table.
- **Fast-moving**: the facts that changed the comparison most all landed
  within the last three months, and will move again:
  - Cursor event and timer wake-ups (2026-08-19);
  - Cursor Builds (2026-08-13);
  - Codex PR triggers (Aug 2026);
  - Claude self-hosted environments going to public beta (Aug 2026);
  - Cloud Run sandboxes for jobs and worker pools (2026-08-05).

  Re-run this review in about three months.
