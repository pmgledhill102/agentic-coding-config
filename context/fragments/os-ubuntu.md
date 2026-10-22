# Ubuntu

True only on **Ubuntu 24.04**: GNU userland, `/bin/sh` is dash. That covers
every cloud sandbox, and WSL (ADR-0020).

- **System Python refuses `pip install`** (PEP 668 `EXTERNALLY-MANAGED`).
  Prefer `uv` or a virtualenv; `--break-system-packages` only on a machine
  that is thrown away
- **`apt-get` needs `-y`**, and `apt-get update` first on a fresh image
