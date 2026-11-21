#!/bin/sh
# Two repos side by side. storefront's docs describe billing-service's retry
# behaviour as it was; billing-service itself has since changed.
set -e
ident() { git config user.name dev && git config user.email dev@example.invalid; }
# Backdated, so nothing in the history looks like it happened a minute ago.
commit_at() {
  GIT_AUTHOR_DATE="$1" GIT_COMMITTER_DATE="$1" git commit -q -a -m "$2"
}

cd "$PROJ"
git init -q -b main .
ident
mkdir -p docs src
cat >README.md <<'MD'
# storefront

The shop front end. Payment is handled by `billing-service`; see
`docs/integrations.md`.
MD
cat >docs/integrations.md <<'MD'
# Integrations

## billing-service

Charges go through `billing-service`, which lives in its own repository
(checked out next to this one, at `../billing-service`).

When a charge fails, billing-service retries it up to 3 times, waiting 30
seconds between attempts, before it marks the order `payment_failed`. The
storefront shows "payment pending" for that window.
MD
cat >src/checkout.py <<'PY'
"""Checkout flow."""

# billing-service retries 3 times at 30 second intervals, so the pending
# banner gives up after 90 seconds.
PENDING_BANNER_TIMEOUT_S = 90


def banner_state(elapsed_s):
    return "pending" if elapsed_s < PENDING_BANNER_TIMEOUT_S else "failed"
PY
git add -A
commit_at "2026-01-12T10:00:00Z" "Storefront skeleton"

mkdir "$RUN_ROOT/billing-service"
cd "$RUN_ROOT/billing-service"
git init -q -b main .
ident
mkdir billing
cat >README.md <<'MD'
# billing-service

Takes payment for storefront orders. Retry policy lives in `billing/retry.py`.
MD
cat >billing/retry.py <<'PY'
"""Retry policy for failed charges."""
import time

MAX_ATTEMPTS = 3
BACKOFF_SECONDS = 30


def charge_with_retry(charge):
    for attempt in range(1, MAX_ATTEMPTS + 1):
        if charge():
            return True
        if attempt < MAX_ATTEMPTS:
            time.sleep(BACKOFF_SECONDS)
    return False
PY
git add -A
commit_at "2026-01-14T10:00:00Z" "Billing service skeleton"
sed -i 's/^MAX_ATTEMPTS = 3/MAX_ATTEMPTS = 5/; s/^BACKOFF_SECONDS = 30/BACKOFF_SECONDS = 120/' billing/retry.py
commit_at "2026-03-03T15:30:00Z" "Raise the retry budget after the processor outage"
