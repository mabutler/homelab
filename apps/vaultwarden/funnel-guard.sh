#!/usr/bin/env bash
# apps/vaultwarden/funnel-guard.sh — may Vaultwarden be published right now?
#
# Exit 0 to allow. Exit non-zero and print why, on stdout or stderr; deploy.sh
# shows that text, skips Funnel, and leaves tailnet access working.
#
# This is called immediately before the port is opened, every deploy. It is not
# a one-time setup check — it re-decides each time, so a vault that drifts into
# an unsafe state stops being republished after the next rebuild.
#
# Deliberately narrow: only conditions where the door being open is actively
# harmful, not everything that could be tidier. A guard that cries wolf gets
# routed around.

set -uo pipefail

APP_ENV=${VAULTWARDEN_ENV:-/etc/homelab/apps/vaultwarden.env}
fail=0
say() { printf '      %s\n' "$*" >&2; fail=1; }

if [[ ! -f "$APP_ENV" ]]; then
    say "$APP_ENV does not exist."
    exit 1
fi

# Open registration on the tailnet is a convenience. Open registration on the
# public internet is an open vault: the hostname is in Certificate Transparency
# logs from the moment the certificate is issued, so "nobody knows the URL" was
# never true.
if grep -qiE '^[[:space:]]*SIGNUPS_ALLOWED[[:space:]]*=[[:space:]]*true' "$APP_ENV"; then
    say "SIGNUPS_ALLOWED is true — anyone reaching the URL could create an account."
    say "Set it false and restart, or finish adding people first."
fi

# Funnel cannot exclude a path, so /admin goes public along with everything
# else — a login form to the panel that can disable 2FA policy and read config.
if grep -qE '^[[:space:]]*ADMIN_TOKEN[[:space:]]*=' "$APP_ENV"; then
    say "ADMIN_TOKEN is set — Funnel would publish /admin too. Comment it out."
fi

# WebAuthn's relying-party ID comes from DOMAIN. Publishing under a name the
# app does not believe in registers security keys against the wrong origin, and
# that is discovered later, by a key that no longer works.
node_dns="$(tailscale status --json 2>/dev/null | jq -r '.Self.DNSName // empty')"
node_dns="${node_dns%.}"
if [[ -n "$node_dns" ]]; then
    conf_domain="$(grep -E '^[[:space:]]*DOMAIN[[:space:]]*=' "$APP_ENV" | head -1)"
    conf_domain="${conf_domain#*=}"
    conf_domain="${conf_domain%\"}"; conf_domain="${conf_domain#\"}"
    if [[ "$conf_domain" != "https://$node_dns" ]]; then
        say "DOMAIN is '$conf_domain' but this node is 'https://$node_dns'."
        say "Fix it before publishing — changing it later breaks every security key."
    fi
fi

exit "$fail"
