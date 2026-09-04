#!/usr/bin/env bash
# lib/publish.sh — turn an app's declared `serve.conf` into live Tailscale
# state. Sourced by deploy.sh and tools/enable-funnel.sh; never executed alone.
#
# WHY THIS EXISTS
#
# `tailscale serve` and `tailscale funnel` settings live in tailscaled's local
# state, not in a file in this repository. A rebuild wipes them. Left as manual
# steps they are the two things you would forget, and the failure mode is a
# server that is up, healthy, passing every check, and unreachable.
#
# So publishing is declared per app, in `apps/<name>/serve.conf`, and converged
# on every deploy:
#
#     SERVE_TARGET=http://127.0.0.1:8222   what to forward to (required)
#     SERVE_PORT=443                       HTTPS port to serve on (default 443)
#     SERVE_PATH=/                         mount point on that port (default /)
#     FUNNEL=yes                           also expose it to the public internet
#     FUNNEL_GUARD=funnel-guard.sh         veto script, relative to the app dir
#
# ONE APP PER PORT, and 443 belongs to Vaultwarden alone. Funnel is enabled per
# PORT, not per path, so anything sharing a port with a funnelled app becomes
# public with it. Tailscale only permits Funnel on 443, 8443 and 10000, so every
# tailnet-only app here is given a port OUTSIDE that set — then no future
# mistake can publish it, whatever anyone types.
#
# The file IS the declaration of intent, in the same sense drives.conf is: a
# committed `FUNNEL=yes` is you saying this app is public, so nothing here asks
# again at deploy time. What it does instead is refuse to act on that
# declaration while the app is in a state that makes publishing dangerous —
# that is FUNNEL_GUARD, and it is the app's own code because only the app knows
# what dangerous means for it.
#
# A guard veto is not a deploy failure. Serve is still applied, so the app is
# reachable on the tailnet; only the public door stays shut, and the next
# deploy after you fix the cause opens it. That is what makes a from-scratch
# build land somewhere sane: no accounts yet means registration is open, which
# means Funnel waits, which is correct.

[[ -n "${_HOMELAB_PUBLISH_SOURCED:-}" ]] && return 0
_HOMELAB_PUBLISH_SOURCED=1

[[ -n "${_HOMELAB_COMMON_SOURCED:-}" ]] \
    || { echo "lib/publish.sh requires lib/common.sh" >&2; exit 1; }

# Fixed key list, same convention as templating: a typo in serve.conf is a
# variable nothing reads, so name them explicitly and clear them between apps.
PUBLISH_KEYS=(SERVE_TARGET SERVE_PORT SERVE_PATH FUNNEL FUNNEL_GUARD)

# Tailscale permits Funnel on these and nothing else.
FUNNELABLE_PORTS=(443 8443 10000)

# load_serve_conf <app-dir> — returns 1 when the app declares no publishing.
load_serve_conf() {
    local dir="$1" conf="$1/serve.conf" k
    for k in "${PUBLISH_KEYS[@]}"; do unset "$k"; done
    [[ -f "$conf" ]] || return 1

    # shellcheck source=/dev/null
    source "$conf"

    [[ -n "${SERVE_TARGET:-}" ]] || die "$conf: SERVE_TARGET is required"
    SERVE_PATH="${SERVE_PATH:-/}"
    SERVE_PORT="${SERVE_PORT:-443}"
    FUNNEL="${FUNNEL:-no}"
    [[ -z "${FUNNEL_GUARD:-}" ]] || FUNNEL_GUARD="$dir/$FUNNEL_GUARD"

    # Catch the contradiction in the file rather than at the moment it matters:
    # a port Funnel cannot use, declared as funnelled, is a typo, and a
    # tailnet-only app parked on a funnelable port is an accident waiting for
    # someone to enable Funnel there.
    local p funnelable=0
    for p in "${FUNNELABLE_PORTS[@]}"; do
        [[ "$SERVE_PORT" == "$p" ]] && funnelable=1
    done
    if [[ "${FUNNEL,,}" == yes ]] && (( ! funnelable )); then
        die "$conf: FUNNEL=yes but SERVE_PORT=$SERVE_PORT — Tailscale only funnels ${FUNNELABLE_PORTS[*]}"
    fi
    if [[ "${FUNNEL,,}" != yes ]] && (( funnelable )); then
        warn "$conf: tailnet-only but parked on $SERVE_PORT, which Funnel can use."
        warn "Move it to a port outside ${FUNNELABLE_PORTS[*]} so it cannot be published by mistake."
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Reading current state
# ---------------------------------------------------------------------------
# `tailscale serve status --json` shape:
#   .Web["host:443"].Handlers["/"].Proxy   -> the forward target
#   .AllowFunnel["host:443"]               -> true when the port is public
_serve_json() { tailscale serve status --json 2>/dev/null || echo '{}'; }

# Keys in .Web and .AllowFunnel are "<magicdns-name>:<port>", so the port is
# matched by suffix rather than assumed to be 443.
serve_is_mounted() {
    local path="$1" target="$2" port="$3" found
    found="$(_serve_json | jq -r --arg p "$path" --arg port ":$port" \
        '[.Web // {} | to_entries[]
          | select(.key | endswith($port))
          | .value.Handlers[$p].Proxy? // empty] | first // empty')"
    [[ "$found" == "$target" ]]
}

funnel_is_on() {
    local port="$1" on
    on="$(_serve_json | jq -r --arg port ":$port" \
        '[.AllowFunnel // {} | to_entries[]
          | select(.key | endswith($port)) | .value] | any')"
    [[ "$on" == "true" ]]
}

node_tags() {
    tailscale status --json 2>/dev/null | jq -r '(.Self.Tags // []) | join(" ")'
}

# The `funnel` node attribute is granted by the tailnet policy, and this
# repository's policy attaches it to a TAG rather than to a user. So an untagged
# node does not get an error from `tailscale funnel` — it gets an interactive
# "visit this URL to allow" prompt, which in an unattended script is worse than
# a refusal: the command appears to run, nothing is published, and the reason
# scrolls past.
#
# Checking the tag ourselves turns that into a sentence you can act on.
node_is_funnel_tagged() {
    local want="${TAILSCALE_TAGS:-}" have t
    [[ -n "$want" ]] || return 0          # nothing declared, nothing to check
    have=" $(node_tags) "
    for t in ${want//,/ }; do
        [[ "$have" == *" $t "* ]] || return 1
    done
    return 0
}

funnel_tag_advice() {
    warn "this node is not tagged ${TAILSCALE_TAGS:-}, so the tailnet policy does"
    warn "not grant it the 'funnel' attribute — that is what Tailscale is asking"
    warn "you to approve. Apply the tag instead:"
    warn "  cd /opt/stack && sudo ./run.sh --only 30"
    warn "or directly (note: 'login', not 'set' — tagging is a re-auth):"
    warn "  sudo tailscale login --advertise-tags=${TAILSCALE_TAGS:-tag:server}"
    warn "It RE-AUTHENTICATES the machine, so run it from tmux, LAN ssh, or the"
    warn "console — not from the Tailscale SSH session it will interrupt."
}

# HTTPS certificates are a tailnet-wide toggle with no CLI. Without it every
# `tailscale serve https` call fails with a certificate error that reads like a
# local problem and is not one.
require_https_certs() {
    local domains
    domains="$(tailscale status --json 2>/dev/null | jq -r '(.CertDomains // []) | length')"
    [[ "$domains" =~ ^[0-9]+$ ]] && (( domains > 0 )) && return 0
    die "this tailnet has no HTTPS certificates enabled, so TLS cannot be terminated here.
Enable it once, in the admin console: DNS -> HTTPS Certificates. It is
tailnet-wide and survives rebuilds of this machine."
}

# ---------------------------------------------------------------------------
# Converging
# ---------------------------------------------------------------------------
# publish_app <app> <app-dir> — idempotent.
publish_app() {
    local app="$1" dir="$2"
    load_serve_conf "$dir" || return 0

    require_cmd tailscale jq
    tailscale status >/dev/null 2>&1 \
        || { warn "$app: not on the tailnet, cannot publish — run bootstrap/30-access.sh"; return 0; }

    require_https_certs

    if ! serve_is_mounted "$SERVE_PATH" "$SERVE_TARGET" "$SERVE_PORT"; then
        log "$app: serving :$SERVE_PORT$SERVE_PATH -> $SERVE_TARGET on the tailnet"
        local -a serve_args=(--bg --https="$SERVE_PORT")
        [[ "$SERVE_PATH" == "/" ]] || serve_args+=(--set-path="$SERVE_PATH")
        run tailscale serve "${serve_args[@]}" "$SERVE_TARGET"
        ok "$app: reachable on the tailnet"
    fi

    [[ "${FUNNEL,,}" == yes ]] || return 0

    if funnel_is_on "$SERVE_PORT"; then
        return 0
    fi

    if ! node_is_funnel_tagged; then
        warn "$app: NOT publishing to the internet —"
        funnel_tag_advice
        warn "$app: tailnet access is up. Deploy again once the tag is applied."
        return 0
    fi

    # The guard runs immediately before the door opens, not one script earlier.
    if [[ -n "${FUNNEL_GUARD:-}" ]]; then
        [[ -x "$FUNNEL_GUARD" ]] || die "$FUNNEL_GUARD is not executable"
        local veto
        if ! veto="$("$FUNNEL_GUARD" 2>&1)"; then
            warn "$app: NOT publishing to the internet —"
            printf '%s\n' "$veto" >&2
            warn "$app: tailnet access is up. Fix the above and deploy again to publish."
            return 0
        fi
    fi

    # Enabled per PORT, not per path: everything mounted on this port becomes
    # public together. load_serve_conf has already refused a port Funnel cannot
    # serve, so this cannot silently do nothing.
    log "$app: enabling Funnel on $SERVE_PORT — reachable from the internet"
    run tailscale funnel --bg --https="$SERVE_PORT" "$SERVE_TARGET"
    ok "$app: published to the public internet"
}
