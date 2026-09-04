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

if (( INSTALL_CHANGED )); then
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
grep_output '^passwordauthentication[[:space:]]+no$' sshd -T \
    || die "sshd still accepts password authentication"
grep_output '^permitrootlogin[[:space:]]+no$' sshd -T \
    || die "sshd still permits root login"

# ---------------------------------------------------------------------------
# Tailscale
# ---------------------------------------------------------------------------
# jq comes along here rather than at the app layer: everything that reads
# Tailscale's state — deploy.sh publishing, verify.sh, the app funnel guards —
# parses `--json` output, and none of them should be the thing that installs a
# package at the moment it needs it.
pkg_install tailscale jq
unit_enable --now tailscaled.service

# TAILSCALE_TAGS from host.conf is a declaration, like every other value in
# that file: this script converges the node to match it. On a from-scratch
# build that happens in the same `tailscale up` you were going to authenticate
# anyway, so it costs nothing.
#
# A tagged node is owned by the tailnet rather than by you: it is not in
# autogroup:member, so the policy gives it no outbound access to anything. That
# is the containment for "a Vaultwarden compromise becomes a tailnet foothold",
# and it is what grants the `funnel` attribute the apps rely on. Tagged nodes
# also have no key expiry, which makes the "disable key expiry" toggle moot.
#
# The policy in apps/vaultwarden/tailnet-policy.hujson must already be applied
# in the admin console — it defines tagOwners for the tag and grants the funnel
# attribute. There is no CLI for that, but it is tailnet state: applied once, it
# survives every rebuild of this machine.
tags_arg=()
if [[ -n "${TAILSCALE_TAGS:-}" ]]; then
    tags_arg=(--advertise-tags="$TAILSCALE_TAGS")
fi

node_has_declared_tags() {
    local have t
    have=" $(tailscale status --json 2>/dev/null | jq -r '(.Self.Tags // []) | join(" ")') "
    for t in ${TAILSCALE_TAGS//,/ }; do
        [[ "$have" == *" $t "* ]] || return 1
    done
    return 0
}

# Re-tagging a node that is already up re-authenticates it, and Tailscale SSH
# sessions to it do not survive that. Running it from the session it is about to
# kill leaves bootstrap half-finished, which is a worse outcome than waiting.
#
# So: detect that specific case, and only that one. Over the LAN, at the
# console, or inside tmux/screen — where the process outlives the connection —
# it just happens.
# SSH_CONNECTION is NOT simply readable here. sudo's env_reset drops it, so
# under `sudo ./run.sh` it is unset — and unset would read as "not over the
# tailnet", which is the permissive answer and exactly the wrong default.
#
# Walk up the process tree instead and take it from the first ancestor that has
# it: the login shell sudo was invoked from. We are root by this point, so
# /proc/<pid>/environ is readable.
ssh_peer() {
    local pid="$PPID" envdata line
    while [[ -n "$pid" && "$pid" -gt 1 ]]; do
        if [[ -r "/proc/$pid/environ" ]]; then
            # Read fully, then match. `tr ... | grep -m1` would exit at the
            # first match and SIGPIPE the producer, which pipefail then reports
            # as failure *because* the match succeeded.
            envdata="$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null || true)"
            line="$(grep -m1 '^SSH_CONNECTION=' <<<"$envdata" || true)"
            if [[ -n "$line" ]]; then
                printf '%s' "${line#SSH_CONNECTION=}"
                return 0
            fi
        fi
        pid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')"
    done
    return 1
}

peer_is_tailnet() {
    local conn peer
    conn="${SSH_CONNECTION:-$(ssh_peer || true)}"
    peer="${conn%% *}"
    # 100.64.0.0/10, the CGNAT range Tailscale assigns from.
    [[ "$peer" =~ ^100\.(6[4-9]|[7-9][0-9]|1[0-1][0-9]|12[0-7])\. ]]
}

in_multiplexer() {
    local pid="$PPID" comm
    while [[ -n "$pid" && "$pid" -gt 1 ]]; do
        comm="$(ps -o comm= -p "$pid" 2>/dev/null || true)"
        [[ "$comm" == tmux* || "$comm" == screen* ]] && return 0
        pid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')"
    done
    return 1
}

if tailscale status >/dev/null 2>&1; then
    dbg "already on the tailnet"
    # `tailscale set` is the idempotent half of `tailscale up`.
    run tailscale set --ssh=true --hostname="$TARGET_HOSTNAME"

    if [[ -n "${TAILSCALE_TAGS:-}" ]] && ! node_has_declared_tags; then
        if peer_is_tailnet && ! in_multiplexer; then
            err "this node is not tagged $TAILSCALE_TAGS, and applying the tag"
            err "re-authenticates the machine — which would drop THIS session,"
            err "leaving the rest of bootstrap unrun. You are connected from"
            err "$(ssh_peer 2>/dev/null | cut -d' ' -f1), which is a tailnet address, and not inside tmux."
            err ""
            err "Reconnect over the LAN, or wrap this in tmux, then:"
            err "  cd /opt/stack && sudo ./run.sh --from 30"
            die "refusing to cut the branch this script is sitting on"
        fi

        # `tailscale login`, not `tailscale set`. Tags change who OWNS the node,
        # so they cannot be set as an ordinary preference — `set` has no
        # --advertise-tags flag at all. `login` is the re-authentication this
        # requires, and unlike `tailscale up` it does not want every other
        # preference restated to avoid resetting them.
        log "applying $TAILSCALE_TAGS (this re-authenticates the machine)"
        warn "a login URL may print below — open it to approve the tag"
        run tailscale login --advertise-tags="$TAILSCALE_TAGS"

        sleep 3
        tailscale status >/dev/null 2>&1 \
            || die "tailscale is unhealthy after tagging — check 'tailscale status'
and the admin console. The tag needs an owner in the policy file
(tagOwners) before this node can claim it."
        node_has_declared_tags \
            || warn "the tag has not appeared yet — if a login URL printed above, approve it"
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
