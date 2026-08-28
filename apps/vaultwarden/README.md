# Vaultwarden

Bitwarden-compatible password server. First application on the stack,
deliberately: every account created after this one gets stored in it.

Tailnet-only for now. Public exposure via Tailscale Funnel is a separate,
scoped step — see [Later: the public door](#later-the-public-door).

---

## First run

### 1. The secrets file

```bash
sudo install -Dm600 /dev/null /etc/homelab/apps/vaultwarden.env
sudo cp /opt/stack/apps/vaultwarden/vaultwarden.env.example \
        /etc/homelab/apps/vaultwarden.env
sudo chmod 600 /etc/homelab/apps/vaultwarden.env
sudo vim /etc/homelab/apps/vaultwarden.env
```

`DOMAIN` is the one value you cannot casually change later — it drives
WebAuthn's relying-party ID, so security keys registered against one domain
stop working if it moves. Get the exact name:

```bash
tailscale status --json | grep -m1 DNSName        # strip the trailing dot
```

Leave `SIGNUPS_ALLOWED=true` for now. Leave `ADMIN_TOKEN` commented out.

**Put a copy of this file in your current password manager.** You cannot
restore it from the vault it configures.

### 2. Deploy and start

```bash
cd /opt/stack
sudo ./deploy.sh vaultwarden
sudo systemctl start vaultwarden
journalctl -u vaultwarden -f
```

First start pulls the image and initialises SQLite; on this hardware give it
a minute.

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

## Later: the public door

Not done yet, and deliberately separate. Funnel publishes this to the open
internet so it is reachable from a work PC that cannot join the tailnet.

Before turning it on, all of this has to happen together:

1. **Tag the node `tag:server` and write real tailnet ACLs.** A container is
   not a security boundary — a Vaultwarden compromise on an untagged node is a
   foothold on the whole tailnet. A tagged node is not owned by a user, so it
   gets no outbound tailnet access. That is the containment.
   Tagging re-authenticates the machine: do it from a session you can afford
   to lose, and confirm you can still get back in.
2. **Enforce TOTP 2FA on both accounts**, and raise the KDF to Argon2id in
   Settings → Security → Keys. Five minutes, and the bulk of the real
   protection.
3. **Unset `ADMIN_TOKEN`.**
4. `tailscale funnel --bg http://127.0.0.1:8222`, on port 443.
5. **Verify from cellular with Tailscale off**, and from the work PC, before
   relying on it.

**The gotcha to remember: Funnel is enabled per _port_, not per path.** Anything
else ever mounted on that port becomes public too. Keep 443 exclusively
Vaultwarden; if another app ever wants `tailscale serve`, give it a different
port so a future you cannot accidentally publish Homepage.

`fail2ban` is not worth adding: behind Funnel, Vaultwarden sees the Tailscale
proxy rather than the real client IP, so bans would hit the wrong address.
Vaultwarden's own rate limiting is the control.

A funnelled URL is also genuinely reachable from outside, which means a free
external uptime monitor can poll it — a better dead-man switch than
absence-of-ping, and the only active external prober available in Stage 1.
Point it at `/alive`, not the login page.
