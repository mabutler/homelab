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
# jq comes along here rather than at the app layer: everything that reads
# Tailscale's state — deploy.sh publishing, verify.sh, the app funnel guards —
# parses `--json` output, and none of them should be the thing that installs a
# package at the moment it needs it.
pkg_install tailscale jq
unit_enable --now tailscaled.service

# Tagging happens HERE, at join time, and not later.
#
# `tailscale set --advertise-tags` re-authenticates the machine, which is a
# rude thing to do to an SSH session halfway through deploying an app. At join
# time you are already authenticating, so it costs nothing — and it means the
# node is tagged before anything is ever published from it, rather than being
# retrofitted afterwards.
#
# A tagged node is owned by the tailnet rather than by you: it is not in
# autogroup:member, so the policy gives it no outbound access to anything. That
# is the containment for "a Vaultwarden compromise becomes a tailnet foothold".
# It also has no key expiry, which makes the "disable key expiry" toggle moot.
#
# The policy in apps/vaultwarden/tailnet-policy.hujson must already be applied
# in the admin console — it defines tagOwners for the tag and grants the funnel
# attribute. There is no CLI for that, but it is tailnet state: applied once, it
# survives every rebuild of this machine.
tags_arg=()
if [[ -n "${TAILSCALE_TAGS:-}" ]]; then
    tags_arg=(--advertise-tags="$TAILSCALE_TAGS")
fi

if [[ -n "$DRY_RUN" ]]; then
    log "would join the tailnet as $TARGET_HOSTNAME (skipped in a dry run)"
elif tailscale status >/dev/null 2>&1; then
    dbg "already on the tailnet"
    # Converge the settings that matter even on a node that joined earlier —
    # `tailscale set` is the idempotent half of `tailscale up`. Tags are left
    # out of this path on purpose: re-advertising them on a live node forces a
    # re-authentication, so changing the tag of a running host is a deliberate
    # act, not something a re-run of bootstrap does to you.
    run tailscale set --ssh=true --hostname="$TARGET_HOSTNAME"
    if [[ -n "${TAILSCALE_TAGS:-}" ]] \
       && ! grep_output "$TAILSCALE_TAGS" tailscale status --json; then
        warn "this node is not tagged $TAILSCALE_TAGS."
        warn "Applying it re-authenticates the machine, so it is not done here:"
        warn "  sudo tailscale set --advertise-tags=$TAILSCALE_TAGS"
    fi
else
    log "joining the tailnet as $TARGET_HOSTNAME${TAILSCALE_TAGS:+ ($TAILSCALE_TAGS)}"
    warn "a login URL will print below — open it, approve this machine, and"
    warn "this script continues on its own once you do"
    # --ssh turns on Tailscale SSH, the second door. --hostname pins the
    # MagicDNS name, which matters later: the Stage 2 migration renames nodes
    # so the new server inherits this name and every client keeps working.
    run tailscale up --ssh --hostname="$TARGET_HOSTNAME" ${tags_arg[@]+"${tags_arg[@]}"}
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

  Tailnet state this host depends on but cannot create, applied once in
  the admin console and surviving every rebuild:

    1. DNS -> HTTPS Certificates, enabled. Without it nothing can be
       served over TLS from this node.
    2. The policy in apps/vaultwarden/tailnet-policy.hujson, defining
       tagOwners for ${TAILSCALE_TAGS:-tag:server} and granting it "funnel".
EOF

ok "access configured"
