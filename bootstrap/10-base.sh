#!/usr/bin/env bash
# bootstrap/10-base.sh — host tuning that has nothing to do with storage,
# access or applications: memory, logs, TRIM and the clock.
#
# Idempotent. Running it twice makes no changes on the second pass, and at
# default verbosity prints nothing. That silence is the test.

# shellcheck source=lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

require_root
require_installed_system
load_host_conf

# --- packages --------------------------------------------------------------
# zram-generator is the only thing missing; fstrim comes from util-linux and
# timesyncd from systemd, both already installed by install/02-pacstrap.sh.
pkg_install zram-generator

# --- compressed swap -------------------------------------------------------
install_file etc/systemd/zram-generator.conf
install_file etc/sysctl.d/99-homelab.conf

# sysctl.d is read at boot; apply now so a fresh run does not need a reboot to
# take effect. --system re-reads every file, which is idempotent by nature.
log "applying sysctl settings"
run sysctl --system >/dev/null

# The generator turns zram-generator.conf into a unit, so systemd has to be
# told to look again before the unit exists to start.
unit_reload
if swapon --show=NAME --noheadings 2>/dev/null | grep -q zram; then
    dbg "zram swap already active"
else
    log "starting zram swap"
    run systemctl start systemd-zram-setup@zram0.service
fi

# --- logs ------------------------------------------------------------------
install_file etc/systemd/journald.conf.d/00-size.conf

# Restart journald only when the cap actually changed. Bouncing it on every
# re-run briefly drops the log stream for whatever is writing at that moment,
# which is a silly price to pay for a no-op.
if (( INSTALL_CHANGED )); then
    log "restarting journald for the new size cap"
    run systemctl restart systemd-journald.service
fi

# --- TRIM ------------------------------------------------------------------
# Weekly discard rather than the continuous `discard` mount option: batched
# TRIM avoids the per-delete latency that continuous discard adds, and this
# SSD reports TRIM support (checked in install/00-preflight.sh).
unit_enable --now fstrim.timer

# --- clock -----------------------------------------------------------------
# Arch enables no time sync by default and install/ does not either, so
# without this the host clock free-runs. That matters more here than it looks:
# TLS certificate validation, Tailscale's key exchange, SnapRAID's timestamp
# comparisons and any correlation between this host's logs and another
# machine's all assume the clock is roughly right.
unit_enable --now systemd-timesyncd.service
run timedatectl set-ntp true

ok "base tuning applied"
