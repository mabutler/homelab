#!/usr/bin/env bash
# tools/enable-funnel.sh — publish Vaultwarden to the public internet.
#
# This is the one deliberate exception to "nothing is public, ever". It exists
# because a password manager you cannot reach from a work PC that will not join
# your tailnet is not a usable password manager.
#
# Everything here is reversible except your attention: once the login page is
# on the open internet, the `ts.net` hostname is in Certificate Transparency
# logs and obscurity buys nothing. The checks below are the price of that.
#
# Run it more than once safely — it converges rather than repeats.

# shellcheck source=lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

require_root
require_installed_system
load_host_conf

APP=vaultwarden
APP_ENV=/etc/homelab/apps/vaultwarden.env
LOCAL_PORT=8222
TAG=tag:server

pkg_install jq tailscale

# ---------------------------------------------------------------------------
# Preconditions
# ---------------------------------------------------------------------------
# A `problem` is something that cannot be true at the moment the door opens —
# it stops the script. Note that this gates PUBLISHING only; none of it
# constrains what you do afterwards, so a refusal here costs a restart, not a
# workflow.
#
# A `caution` is worth seeing but not worth blocking on. Cautions are collected
# and printed on the confirmation screen, immediately above the typed prompt,
# rather than scrolling past while the preconditions run.
#
# Nothing is changed until both lists have been printed.
fail=0
cautions=()
problem() { err "$*"; fail=$(( fail + 1 )); }
caution() { cautions+=("$*"); }

systemctl is-active --quiet "$APP.service" \
    || problem "$APP is not running — publish something that works first"

[[ -f "$APP_ENV" ]] || problem "$APP_ENV does not exist"

if [[ -f "$APP_ENV" ]]; then
    # Registration must be closed at the moment the door opens. Otherwise
    # anyone who has the URL — and Certificate Transparency means the name is
    # published as soon as the certificate is issued — can create an account.
    #
    # This gates publishing, not the setting: opening registration later to add
    # a family member needs nothing from this script. See the README.
    if grep -qiE '^[[:space:]]*SIGNUPS_ALLOWED[[:space:]]*=[[:space:]]*true' "$APP_ENV"; then
        problem "SIGNUPS_ALLOWED is true. Create your accounts, set it false, restart, then run this again."
    fi

    # Funnel cannot exclude a path, so /admin would be publicly reachable.
    if grep -qE '^[[:space:]]*ADMIN_TOKEN[[:space:]]*=' "$APP_ENV"; then
        problem "ADMIN_TOKEN is set. Comment it out — Funnel publishes /admin along with everything else."
    fi

    if ! grep -qE '^[[:space:]]*LOGIN_RATELIMIT_SECONDS[[:space:]]*=' "$APP_ENV"; then
        caution "LOGIN_RATELIMIT_SECONDS is not set — Vaultwarden's own rate limiting
      is the only brute-force control you get here. fail2ban cannot help:
      behind Funnel every request arrives from the Tailscale proxy."
    fi
fi

# The DOMAIN Vaultwarden believes in has to be the name Funnel will serve.
# WebAuthn's relying-party ID comes from it, so a mismatch means security keys
# registered now stop working later.
ts_json="$(tailscale status --json 2>/dev/null || true)"
[[ -n "$ts_json" ]] || problem "tailscale status failed — is tailscaled running?"

node_dns=''
if [[ -n "$ts_json" ]]; then
    node_dns="$(jq -r '.Self.DNSName // empty' <<<"$ts_json")"
    node_dns="${node_dns%.}"
    [[ -n "$node_dns" ]] || problem "could not read this node's MagicDNS name"
fi

if [[ -n "$node_dns" && -f "$APP_ENV" ]]; then
    conf_domain="$(grep -E '^[[:space:]]*DOMAIN[[:space:]]*=' "$APP_ENV" | head -1)"
    conf_domain="${conf_domain#*=}"
    conf_domain="${conf_domain%\"}"; conf_domain="${conf_domain#\"}"
    if [[ "$conf_domain" != "https://$node_dns" ]]; then
        problem "DOMAIN is '$conf_domain' but this node is 'https://$node_dns'.
Fix DOMAIN before publishing — it drives WebAuthn's relying-party ID, and
changing it later invalidates every security key registered against it."
    fi
fi

# tailscale serve should already be proven on the tailnet. Funnel is that same
# mount made public; publishing something that was never reachable privately is
# debugging in the worst possible place.
serve_json="$(tailscale serve status --json 2>/dev/null || true)"
if [[ -z "$serve_json" ]] || ! grep -q "127.0.0.1:$LOCAL_PORT" <<<"$serve_json"; then
    problem "tailscale serve is not forwarding to 127.0.0.1:$LOCAL_PORT.
Run:  sudo tailscale serve --bg https / http://127.0.0.1:$LOCAL_PORT
and confirm the site loads from a tailnet device first."
fi

(( fail == 0 )) || die "$fail precondition(s) failed — nothing has been changed"
ok "preconditions passed"

# ---------------------------------------------------------------------------
# Things this script cannot check
# ---------------------------------------------------------------------------
cat >&2 <<EOF

  ────────────────────────────────────────────────────────────
  About to publish https://$node_dns to the public internet.
EOF

# Printed here, immediately above the typed confirmation, rather than scrolled
# past thirty lines ago.
if (( ${#cautions[@]} )); then
    printf '\n  %d thing(s) you should look at first:\n\n' "${#cautions[@]}" >&2
    for c in "${cautions[@]}"; do
        printf '    ! %s\n\n' "$c" >&2
    done
fi

cat >&2 <<EOF

  Two things no script can verify, and they are the bulk of the
  real protection:

    * TOTP two-factor is enabled on BOTH accounts, enforced by
      Organization policy.
    * The KDF is Argon2id with raised iterations
      (web vault → Settings → Security → Keys).

  And one thing that must already be true in the admin console:

    * The tailnet policy from apps/vaultwarden/tailnet-policy.hujson
      is applied, defining tagOwners for $TAG and granting it the
      "funnel" attribute.

  Applying the tag RE-AUTHENTICATES this machine. If you are on
  Tailscale SSH right now, that session may drop. Run this from
  tmux, or over LAN ssh, or at the console.
  ────────────────────────────────────────────────────────────
EOF

confirm "PUBLISH $node_dns"

# ---------------------------------------------------------------------------
# Tag the node
# ---------------------------------------------------------------------------
# A tagged node is owned by the tailnet rather than by you, which is what
# removes its outbound access under the policy — the containment for
# "Vaultwarden compromise becomes a tailnet foothold".
if grep_output "\"$TAG\"" jq -r '.Self.Tags // [] | tostring' <<<"$ts_json"; then
    dbg "already tagged $TAG"
else
    log "advertising $TAG (this re-authenticates the machine)"
    run tailscale set --advertise-tags="$TAG"

    if [[ -z "$DRY_RUN" ]]; then
        sleep 3
        tailscale status >/dev/null 2>&1 \
            || die "tailscale is not healthy after tagging — check 'tailscale status' and the admin console before continuing"
        ok "still connected after tagging"
    fi
fi

# ---------------------------------------------------------------------------
# Funnel
# ---------------------------------------------------------------------------
# --bg persists it in tailscaled's state across reboots; without it you get a
# foreground session that dies with your shell.
#
# Funnel accepts only 443, 8443 and 10000. Use 443 so the URL stays clean —
# and note it is enabled per PORT, not per path: anything else ever mounted on
# 443 becomes public too. Keep 443 exclusively Vaultwarden.
log "enabling Funnel on 443 -> 127.0.0.1:$LOCAL_PORT"
run tailscale funnel --bg "http://127.0.0.1:$LOCAL_PORT"

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
    5. You can still get in: ssh over Tailscale AND over the LAN.
       The tag change re-authenticated this node.

  A port scan of your home IP will NOT show this. Funnel is an
  outbound tunnel and never touches your router. A clean scan
  does not mean Vaultwarden is private — do not let a future you
  draw that conclusion.
  ────────────────────────────────────────────────────────────
EOF
fi

ok "Funnel enabled for $node_dns"
