#!/usr/bin/env bash
# tools/check-drives.sh — verify the attached drives against drives.conf.
#
# Read-only and unprivileged. Safe to run at any time, on the live ISO or on
# the installed system, before or after provisioning. Exits non-zero if any
# drive fails, which is what makes it usable as a gate.
#
# The same check runs inside install/00-preflight.sh before anything is
# destroyed, and inside bootstrap/40-storage.sh before the pool is assembled.

# shellcheck source=lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

require_cmd lsblk
load_drives_conf
report_drives
