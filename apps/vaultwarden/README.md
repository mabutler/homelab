# Vaultwarden

Bitwarden-compatible password server. First application on the stack,
deliberately: every account created after this one gets stored in it.

Tailnet-only for now. Public exposure via Tailscale Funnel is a separate,
scoped step — see [The public door](#the-public-door--funnel).

---

## First run

### 1. The secrets file

Same contract as `host.conf`: the repository ships an example, you make the
real file. `deploy.sh` will stop and print exactly this if you skip it.

```bash
cd /opt/stack
sudo cp apps/vaultwarden/vaultwarden.env.example \
        apps/vaultwarden/vaultwarden.env
sudo vim apps/vaultwarden/vaultwarden.env
```

Permissions and the symlink into `/etc/homelab/apps/` are handled for you on
the next `deploy.sh` — you never need to `chmod` or `ln` anything.

The file you edit lives in the repo (gitignored) next to the unit that
consumes it; the symlink is what makes every secret on this host discoverable
in one directory — one thing to back up, one thing to restore.

`DOMAIN` is the one value you cannot casually change later — it drives
WebAuthn's relying-party ID, so security keys registered against one domain
stop working if it moves. Get the exact name:

```bash
tailscale status --json | grep -m1 DNSName        # strip the trailing dot
```

Leave `SIGNUPS_ALLOWED=true` for now. Leave `ADMIN_TOKEN` commented out.

**Put a copy of this file in your current password manager.** You cannot
restore it from the vault it configures.

### 2. Deploy

```bash
cd /opt/stack && sudo ./deploy.sh vaultwarden
```

`deploy.sh` links the unit, reloads systemd so Quadlet generates the service,
starts it, and reports whether it actually came up. Boot-time startup needs no
`systemctl enable` — Quadlet honours the `[Install]` section in the
`.container` file.

First start pulls the image and initialises SQLite; on this hardware give it a
minute. `journalctl -u vaultwarden -f` if you want to watch.

### 3. Publish it on the tailnet

Vaultwarden listens on `127.0.0.1:8222` only. `tailscale serve` terminates TLS
and forwards from the tailnet:

```bash
sudo tailscale serve --bg https / http://127.0.0.1:8222
tailscale serve status
```

Real HTTPS matters here specifically: the official Bitwarden clients refuse to
talk to a server over plain HTTP, so this is not cosmetic.

Then open `https://fidelacchius.<tailnet>.ts.net` from a device on the tailnet.

### 4. Create both accounts, then close the door

Register your account and your partner's through the web vault. Then:

```bash
sudo vim /etc/homelab/apps/vaultwarden.env   # SIGNUPS_ALLOWED=false
sudo systemctl restart vaultwarden
```

Verify it took: the registration page should refuse.

### 5. Point the clients at it

In every Bitwarden app — desktop, browser extension, phone — use
**Self-hosted** on the login screen and give it the same `DOMAIN` URL.

### 6. A Family organisation

Create an Organization in the web vault for credentials you both need. Personal
vaults stay personal; shared things live there.

---

## Operating

```bash
systemctl status vaultwarden
journalctl -u vaultwarden -n 100
systemctl restart vaultwarden
```

State is `/opt/appdata/vaultwarden` — SQLite database, attachments, RSA keys,
icon cache. All of it.

**Never copy `db.sqlite3` from a running server as a backup.** A live-copied
SQLite file restores as a corrupt database, and you find out at the worst
moment. The correct form is:

```bash
sudo sqlite3 /opt/appdata/vaultwarden/db.sqlite3 ".backup '/tmp/vw.sqlite3'"
```

That becomes a pre-hook in the restic job at Phase 4.

### Adding someone later

Registration is closed in steady state, so adding an account is a deliberate
open-register-close cycle:

```bash
sudo vim /etc/homelab/apps/vaultwarden.env   # SIGNUPS_ALLOWED=true
sudo systemctl restart vaultwarden
# they register at the DOMAIN URL
sudo vim /etc/homelab/apps/vaultwarden.env   # SIGNUPS_ALLOWED=false
sudo systemctl restart vaultwarden
```

Confirm it closed again: the registration page should refuse.

**Once Funnel is on, that window is open to the internet, not to the tailnet.**
Minutes, not days — and do not leave it true overnight because the person is
"going to get to it tomorrow". If they are a tailnet device, turn Funnel off
for the duration instead:

```bash
sudo tailscale funnel --https=443 off     # ... register ...
sudo tailscale funnel --bg http://127.0.0.1:8222
```

`INVITATIONS_ALLOWED` with an Organization invite is the better long-term
answer and does not require opening registration at all; it needs SMTP
configured, which this deployment does not have yet.

### The admin panel

Off by default, deliberately. To use it, uncomment `ADMIN_TOKEN` with an
Argon2 hash (not a password):

```bash
podman run --rm -it docker.io/vaultwarden/server:latest /vaultwarden hash
```

Then restart, do what you need at `/admin`, and comment it out again. Once
Funnel is on this matters more — Funnel cannot exclude `/admin` by path, so an
enabled panel is a publicly reachable login form.

### Updates

`AutoUpdate=registry` on the `latest` tag, applied by the daily
`podman-auto-update` timer at 05:00. Podman rolls back automatically if the new
image fails to start.

This is the one container where a stalled update is a security problem rather
than staleness, because it is the only service that will have a public
listener. "Confirm Vaultwarden's image is current" belongs in the quarterly
ritual.

---

## The public door — Funnel

Publishing this to the open internet is a scripted, gated step:

```bash
cd /opt/stack && sudo ./tools/enable-funnel.sh
```

**Before it will do anything**, apply the tailnet policy in
[`tailnet-policy.hujson`](tailnet-policy.hujson) in the Tailscale admin console
(Access Controls). There is no CLI for that — the console is authoritative and
the file here is a reference copy to keep in sync by hand.

It refuses unless: Vaultwarden is running, `SIGNUPS_ALLOWED` is false,
`ADMIN_TOKEN` is unset, `DOMAIN` matches this node's real MagicDNS name, and
`tailscale serve` is already forwarding to `127.0.0.1:8222`. Then it tags the
node, enables Funnel on 443, and prints the verification gate.

**Those gate publishing, not the settings themselves.** Opening registration or
the admin panel later needs nothing from this script — see
[Adding someone later](#adding-someone-later). The refusals only mean the door
is not opened *while* something is wide open behind it.

Softer notes — currently just an unset `LOGIN_RATELIMIT_SECONDS` — are printed
on the confirmation screen, directly above the typed `PUBLISH <host>` prompt,
without blocking.

Two things it cannot check, and they are the bulk of the real protection:
**TOTP 2FA on both accounts** (enforced by Organization policy) and **Argon2id
KDF with raised iterations**. Do both in the web vault first.

### Why tagging matters

A container is not a security boundary. A Vaultwarden compromise on an
untagged node would be a foothold on the whole tailnet. A tagged node is owned
by the tailnet rather than by you, so it is not in `autogroup:member` and gets
no outbound access to anything. Your phone reaches it; it reaches nothing.

Applying the tag **re-authenticates the machine**, so run the script from
`tmux`, from LAN ssh, or at the console — not from the Tailscale SSH session
you are about to interrupt.

Tagged nodes also have no key expiry, which makes the "disable key expiry"
toggle moot.

### The gotchas

**Funnel is enabled per _port_, not per path.** Anything else ever mounted on
443 becomes public too. Keep 443 exclusively Vaultwarden; if another app wants
`tailscale serve`, give it a different port so a future you cannot accidentally
publish Homepage.

**A port scan of your home IP will not show this.** Funnel is an outbound
tunnel and never touches your router. A clean scan does not mean Vaultwarden is
private.

**`fail2ban` would not help.** Behind Funnel, Vaultwarden sees the Tailscale
proxy rather than the real client IP, so bans would hit the wrong address.
Vaultwarden's own rate limiting is the control.

### One thing it buys you

A funnelled URL is genuinely reachable from outside, so a free external uptime
monitor can poll it — an active external prober, which is a better dead-man
switch than absence-of-ping and the only one available in Stage 1. Point it at
`/alive`, not the login page.
