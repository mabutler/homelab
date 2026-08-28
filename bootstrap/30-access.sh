#!/usr/bin/env bash
# bootstrap/30-access.sh — the two independent ways into this machine.
#
# sshd on the LAN, keys only. Tailscale SSH over the tailnet. They share no
# code path: a mistake in sshd_config does not cost you Tailscale, and a
# tailnet outage does not cost you sshd. That redundancy is the whole point,
# and it is why this script re-applies the sshd config rather than assuming
# install/ got there first.
#
# Idempotent, except that joining the tailnet needs you to approve the machine
# in a browser once.

# shellcheck source=lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

require_root
require_installed_system
load_host_conf

# ---------------------------------------------------------------------------
# sshd
# ---------------------------------------------------------------------------
# install/03-chroot.sh already put this file in place, and re-installing it is
# a no-op. It is repeated here because bootstrap/ is the definition of host
# state: editing files/etc/ssh/sshd_config.d/10-hardening.conf and running
# run.sh has to be enough to change a live host, without a reinstall.
install_file etc/ssh/sshd_config.d/10-hardening.conf

# Guarded on DRY_RUN as well: under a dry run the file was never written, so
# validating and reloading would be acting on a change that did not happen.
if (( INSTALL_CHANGED )) && [[ -z "$DRY_RUN" ]]; then
    # Validate before asking sshd to adopt it. A syntactically bad drop-in that
    # sshd refuses to load leaves the running daemon on its old config until
    # something restarts it — and then you are locked out at the worst moment.
    sshd -t || die "the sshd drop-in does not parse — not reloading, current config left in place"

    # reload, not restart: existing sessions survive, including the one you are
    # almost certainly running this from.
    log "reloading sshd"
    run systemctl reload sshd.service
fi

# Assert the effective config, not just that the file parses. A drop-in that is
# never read parses perfectly.
if [[ -z "$DRY_RUN" ]]; then
    grep_output '^passwordauthentication[[:space:]]+no$' sshd -T \
        || die "sshd still accepts password authentication"
    grep_output '^permitrootlogin[[:space:]]+no$' sshd -T \
        || die "sshd still permits root login"
fi

# ---------------------------------------------------------------------------
# Tailscale
# ---------------------------------------------------------------------------
pkg_install tailscale
unit_enable --now tailscaled.service

if [[ -n "$DRY_RUN" ]]; then
    log "would join the tailnet as $TARGET_HOSTNAME (skipped in a dry run)"
elif tailscale status >/dev/null 2>&1; then
    dbg "already on the tailnet"
    # Converge the settings that matter even on a node that joined earlier —
    # `tailscale set` is the idempotent half of `tailscale up`.
    run tailscale set --ssh=true --hostname="$TARGET_HOSTNAME"
else
    log "joining the tailnet as $TARGET_HOSTNAME"
    warn "a login URL will print below — open it, approve this machine, and"
    warn "this script continues on its own once you do"
    # --ssh turns on Tailscale SSH, the second door. --hostname pins the
    # MagicDNS name, which matters later: the Stage 2 migration renames nodes
    # so the new server inherits this name and every client keeps working.
    run tailscale up --ssh --hostname="$TARGET_HOSTNAME"
fi

# ---------------------------------------------------------------------------
# Verify both doors, while you still have a working session to fix them from
# ---------------------------------------------------------------------------
if [[ -z "$DRY_RUN" ]]; then
    systemctl is-active --quiet sshd.service \
        || die "sshd is not running"
    systemctl is-active --quiet tailscaled.service \
        || die "tailscaled is not running"

    ts_ip="$(tailscale ip -4 2>/dev/null || true)"
    if [[ -z "$ts_ip" ]]; then
        warn "no tailnet address yet — the machine has not finished joining"
    else
        ok "tailnet address: $ts_ip"
    fi
fi

cat >&2 <<EOF

  Two things to do from another device before trusting this:

    1. ssh $ADMIN_USER@$TARGET_HOSTNAME       over the tailnet, from off-network
    2. ssh $ADMIN_USER@<lan-address>          the LAN path, still key-only

  Tailscale SSH and sshd are separate doors. Confirm both, because the
  value of having two is that you never test them at the same time again.

  Not done here, on purpose: tagging this node tag:server and writing the
  tailnet ACL policy. That belongs with the Vaultwarden Funnel work, and
  applying a tag re-authenticates the machine — a bad thing to do casually
  from an SSH session you would like to keep.
EOF

ok "access configured"
