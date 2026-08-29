#!/usr/bin/env bash
# apps/vaultwarden/funnel-guard.sh — may Vaultwarden be published right now?
#
# Exit 0 to allow. Exit non-zero and print why, on stdout or stderr; deploy.sh
# shows that text, skips Funnel, and leaves tailnet access working.
#
# Called immediately before the port is opened, every deploy. Not a one-time
# setup check — it re-decides each time, so a vault that drifts into an unsafe
# state stops being republished.
#
# ASSERT THE EFFECTIVE CONFIG, NOT THE DECLARED ONE.
#
# This script used to read the .env file. That file is what Vaultwarden was
# CONFIGURED with, not what it is RUNNING with: systemd reads EnvironmentFile
# once at container start, so an edit that has not been followed by a restart
# is inert. The file said SIGNUPS_ALLOWED=false while the running container had
# it true, and a guard reading the file would have cheerfully published an open
# registration page to the internet while reporting that registration was shut.
#
# Same lesson as `sshd -t` proving a file parses rather than that it is read.
# Ask the process what it believes.

set -uo pipefail

APP_ENV=${VAULTWARDEN_ENV:-/etc/homelab/apps/vaultwarden.env}
DATA_DIR=${VAULTWARDEN_DATA:-/opt/appdata/vaultwarden}
CTR=${VAULTWARDEN_CONTAINER:-vaultwarden}

fail=0
say() { printf '      %s\n' "$*" >&2; fail=1; }

if [[ ! -f "$APP_ENV" ]]; then
    say "$APP_ENV does not exist."
    exit 1
fi

# ---------------------------------------------------------------------------
# What is the process actually running with?
# ---------------------------------------------------------------------------
effective=''
if [[ "$(podman container inspect -f '{{.State.Running}}' "$CTR" 2>/dev/null || true)" == "true" ]]; then
    effective="$(podman exec "$CTR" printenv 2>/dev/null || true)"
fi

declared="$(cat -- "$APP_ENV")"

if [[ -z "$effective" ]]; then
    # Not running, or exec refused. Fall back to the file, but say so — the
    # answer is now a prediction rather than an observation.
    say "cannot read $CTR's live environment (is it running?), so the checks"
    say "below read $APP_ENV instead. That is the DECLARED config; a setting"
    say "edited without a restart would not show here."
    effective="$declared"
fi

# value_of <KEY> — from the effective environment, last definition wins.
value_of() {
    local line
    line="$(grep -iE "^[[:space:]]*$1[[:space:]]*=" <<<"$effective" | tail -1)"
    line="${line#*=}"
    line="${line%\"}"; line="${line#\"}"
    line="${line%\'}"; line="${line#\'}"
    printf '%s' "${line%$'\r'}"
}

# ---------------------------------------------------------------------------
# Drift: the file and the process disagree
# ---------------------------------------------------------------------------
# Not fatal on its own, but it means a pending restart is carrying a change you
# think is already applied — worth saying out loud whichever way it points.
for key in SIGNUPS_ALLOWED ADMIN_TOKEN DOMAIN; do
    file_val="$(grep -iE "^[[:space:]]*${key}[[:space:]]*=" <<<"$declared" | tail -1 || true)"
    file_val="${file_val#*=}"
    live_val="$(value_of "$key")"
    if [[ -n "$file_val$live_val" && "${file_val//\"/}" != "$live_val" ]]; then
        say "$key differs: $APP_ENV says '${file_val:-<unset>}', the running"
        say "container has '${live_val:-<unset>}'. Restart it to apply the file:"
        say "  systemctl restart vaultwarden"
    fi
done

# ---------------------------------------------------------------------------
# The conditions themselves
# ---------------------------------------------------------------------------
# Settings saved from the admin page persist to config.json and take priority
# over the environment, which would make everything above a guess.
if [[ -f "$DATA_DIR/config.json" ]]; then
    say "$DATA_DIR/config.json exists — settings saved from the admin page live"
    say "there and override the environment, so these checks cannot be trusted."
    say "Reconcile the two (or remove config.json) before publishing."
fi

# Open registration on the tailnet is a convenience. Open registration on the
# public internet is an open vault: the hostname is in Certificate Transparency
# logs from the moment the certificate is issued, so "nobody knows the URL" was
# never true.
if [[ "$(value_of SIGNUPS_ALLOWED)" == [Tt]rue ]]; then
    say "SIGNUPS_ALLOWED is true in the RUNNING container — anyone reaching the"
    say "URL could create an account. Set it false and restart."
fi

# Funnel cannot exclude a path, so /admin goes public along with everything
# else — a login form to the panel that can disable 2FA policy and read config.
if [[ -n "$(value_of ADMIN_TOKEN)" ]]; then
    say "ADMIN_TOKEN is set — Funnel would publish /admin too. Comment it out."
fi

# WebAuthn's relying-party ID comes from DOMAIN. Publishing under a name the
# app does not believe in registers security keys against the wrong origin, and
# that is discovered later, by a key that no longer works.
node_dns="$(tailscale status --json 2>/dev/null | jq -r '.Self.DNSName // empty')"
node_dns="${node_dns%.}"
if [[ -n "$node_dns" ]]; then
    conf_domain="$(value_of DOMAIN)"
    if [[ "$conf_domain" != "https://$node_dns" ]]; then
        say "DOMAIN is '$conf_domain' but this node is 'https://$node_dns'."
        say "Fix it before publishing — changing it later breaks every security key."
    fi
fi

exit "$fail"
