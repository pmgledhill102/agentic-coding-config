# Cloud sandbox

True only in an ephemeral cloud sandbox. Nothing here applies on a
workstation, and the workstation fragment is never composed into a sandbox
profile — see ADR-0018 principle 5.

## This container is the whole environment

There is no chezmoi here, and `~/.claude/` is not chezmoi-managed. It is
written by `cloud/bootstrap.sh` when the environment is built, so a file
found there arrived with the container rather than from a workstation.

Anything installed by hand is lost when the container is reclaimed, and is
invisible to the next session. Changes that must survive belong in the repo
or in the environment's setup script.

## Capabilities available here

- **Brokered Google Cloud access**, when `CREDENTIAL_BROKER_URL` is set in
  the environment. Request it with the `gcp-credentials` skill rather than
  asking a human to run `gcloud` commands by hand. The trigger is not "I
  need to change something in GCP" but **"I am about to assert something
  about live GCP state"**.
- **Skills delivered by the bootstrap**, listed in `cloud/README.md`.
  A command that exists on the workstation is not necessarily present here.
