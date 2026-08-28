#!/usr/bin/env bash
# tools/enable-funnel.sh — publish an app to the public internet, by hand.
#
#   ./tools/enable-funnel.sh [app]      default: vaultwarden
#   ./tools/enable-funnel.sh --off app  take it off the internet again
#
# YOU DO NOT NORMALLY NEED THIS. `deploy.sh` publishes every app that declares
# FUNNEL=yes in its serve.conf, on every deploy, so a from-scratch rebuild ends
# with the public door already open. This script exists for the two cases that
# are not a deploy:
#
#   * turning Funnel off for a few minutes — while you open registration to
#     add someone, say — and back on afterwards.
#   * publishing once without a deploy, after fixing whatever the app's
#     funnel-guard.sh was objecting to.
#
# It runs the same guard deploy.sh does, and asks for confirmation, because a
# human running this by hand is doing something outside the declared state.

# shellcheck source=lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"
# shellcheck source=lib/publish.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/publish.sh"

require_root
require_installed_system
load_host_conf

APP=vaultwarden
OFF=0
while (( $# )); do
    case "$1" in
        --off) OFF=1 ;;
        -v|--verbose) VERBOSE=1 ;;
        -*) die "unknown argument: $1" ;;
        *) APP="$1" ;;
    esac
    shift
done

APP_DIR="$REPO_ROOT/apps/$APP"
[[ -d "$APP_DIR" ]] || die "no such app: $APP"

require_cmd tailscale jq
load_serve_conf "$APP_DIR" || die "$APP declares no serve.conf — nothing to publish"

node_dns="$(tailscale status --json 2>/dev/null | jq -r '.Self.DNSName // empty')"
node_dns="${node_dns%.}"
[[ -n "$node_dns" ]] || die "could not read this node's MagicDNS name — is tailscaled running?"

# ---------------------------------------------------------------------------
# Off
# ---------------------------------------------------------------------------
# Leaves `tailscale serve` alone, so the app stays reachable on the tailnet.
# Only the public door closes.
if (( OFF )); then
    funnel_is_on || { ok "$APP is already tailnet-only"; exit 0; }
    log "closing the public door for $APP"
    run tailscale funnel --https=443 off
    ok "$node_dns is no longer public. Tailnet access is unchanged."
    warn "the next deploy.sh will publish it again — serve.conf still says FUNNEL=yes"
    exit 0
fi

# ---------------------------------------------------------------------------
# On
# ---------------------------------------------------------------------------
[[ "${FUNNEL,,}" == yes ]] \
    || die "$APP/serve.conf does not say FUNNEL=yes. Change the declaration rather than working around it."

systemctl is-active --quiet "$APP.service" \
    || die "$APP is not running — publish something that works first"

serve_is_mounted "$SERVE_PATH" "$SERVE_TARGET" \
    || die "$APP is not served on the tailnet yet. Run deploy.sh first, and confirm
the site loads from a tailnet device before making it public."

if [[ -n "${FUNNEL_GUARD:-}" ]] && ! "$FUNNEL_GUARD"; then
    die "$APP's funnel guard says no — see above. Nothing has been changed."
fi

if funnel_is_on; then
    ok "$node_dns is already public"
    exit 0
fi

cat >&2 <<EOF

  ────────────────────────────────────────────────────────────
  About to publish https://$node_dns to the public internet.

  Two things no script can verify, and they are the bulk of the
  real protection:

    * TOTP two-factor is enabled on BOTH accounts, enforced by
      Organization policy.
    * The KDF is Argon2id with raised iterations
      (web vault → Settings → Security → Keys).

  Funnel is enabled per PORT, not per path. Everything mounted on
  443 goes public together — keep 443 exclusively $APP.
  ────────────────────────────────────────────────────────────
EOF

confirm "PUBLISH $node_dns"

log "enabling Funnel on 443 -> $SERVE_TARGET"
run tailscale funnel --bg "$SERVE_TARGET"

if [[ -z "$DRY_RUN" ]]; then
    tailscale funnel status >&2 || warn "could not read funnel status"

    cat >&2 <<EOF

  ────────────────────────────────────────────────────────────
  Verification gate — do all of these before relying on it:

    1. Phone, Tailscale OFF, on cellular: load
       https://$node_dns — log in, unlock.
    2. The work PC: same.
    3. Reboot this machine and confirm Funnel returns on its own.
    4. Bitwarden apps on tailnet devices still sync.

  A port scan of your home IP will NOT show this. Funnel is an
  outbound tunnel and never touches your router. A clean scan
  does not mean $APP is private — do not let a future you draw
  that conclusion.
  ────────────────────────────────────────────────────────────
EOF
fi

ok "Funnel enabled for $node_dns"
