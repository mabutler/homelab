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
starts it, reports whether it actually came up, **and publishes it** — see
[`serve.conf`](serve.conf). Boot-time startup needs no `systemctl enable` —
Quadlet honours the `[Install]` section in the `.container` file.

First start pulls the image and initialises SQLite; on this hardware give it a
minute. `journalctl -u vaultwarden -f` if you want to watch.

Vaultwarden binds `127.0.0.1:8222` and nothing else, so `tailscale serve` is
what makes it reachable at all. That is not a manual step: `serve.conf` declares
it and every deploy converges the machine to match, because serve state lives in
tailscaled and does not survive a rebuild.

Real HTTPS matters here specifically — the official Bitwarden clients refuse to
talk to a server over plain HTTP — which is why the tailnet's **HTTPS
Certificates** toggle (admin console → DNS) has to be on. `deploy.sh` stops with
that instruction if it is not.

On a first-ever build it will report the tailnet mount and then decline to open
the public door, because `SIGNUPS_ALLOWED` is still true. That is the intended
sequence, not a failure — continue to step 3.

```bash
tailscale serve status     # confirm the mount
```

Then open `https://fidelacchius.<tailnet>.ts.net` from a device on the tailnet.

### 3. Create both accounts, then close the door

Register your account and your partner's through the web vault. Then:

```bash
sudo vim /etc/homelab/apps/vaultwarden.env   # SIGNUPS_ALLOWED=false
sudo systemctl restart vaultwarden
sudo ./deploy.sh vaultwarden                 # now it publishes
```

Verify it took: the registration page should refuse.

That third command is the whole Funnel step. On a *rebuild* — where restored
state already contains the accounts and `SIGNUPS_ALLOWED` is already false —
none of this happens and `deploy.sh` publishes on the first run.

### 4. Point the clients at it

In every Bitwarden app — desktop, browser extension, phone — use
**Self-hosted** on the login screen and give it the same `DOMAIN` URL.

### 5. A Family organisation

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
"going to get to it tomorrow". If they are on a tailnet device, close the public
door for the duration instead:

```bash
cd /opt/stack
sudo ./tools/enable-funnel.sh --off vaultwarden    # ... they register ...
sudo ./tools/enable-funnel.sh vaultwarden
```

Note that a `deploy.sh` run in between will republish it — `serve.conf` is still
the declaration, and `--off` is a temporary override of it.

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

`FUNNEL=yes` in [`serve.conf`](serve.conf) is the declaration that this app is
public, and `deploy.sh` acts on it. There is no separate publish step and
nothing to remember after a rebuild.

Two pieces of **tailnet** state have to exist first. Both are applied once in
the admin console, belong to the tailnet rather than to this machine, and
therefore survive every rebuild:

1. **DNS → HTTPS Certificates**, enabled. Without it nothing can be served over
   TLS from this node at all — not even on the tailnet.
2. The policy in [`tailnet-policy.hujson`](tailnet-policy.hujson) under Access
   Controls, defining `tagOwners` for `tag:server` and granting it the `funnel`
   attribute. There is no CLI for this; the console is authoritative and the
   file here is a reference copy to keep in sync by hand.

The node claims that tag at **join** time, from `TAILSCALE_TAGS` in `host.conf`
— see [Why tagging matters](#why-tagging-matters).

### The guard

Before the port opens, `deploy.sh` runs
[`funnel-guard.sh`](funnel-guard.sh), which vetoes publishing if
`SIGNUPS_ALLOWED` is true, `ADMIN_TOKEN` is set, or `DOMAIN` does not match this
node's real MagicDNS name.

A veto is **not a deploy failure**. The tailnet mount still goes up, so the app
is reachable; only the public door stays shut, and the next deploy after you fix
the cause opens it. That is what makes a from-scratch build land somewhere sane:
no accounts yet means registration is open, which means Funnel waits.

It re-decides on every deploy rather than once at setup, so a vault that drifts
into an unsafe state stops being republished.

### Doing it by hand

[`tools/enable-funnel.sh`](../../tools/enable-funnel.sh) is the manual path, for
the cases that are not a deploy:

```bash
sudo ./tools/enable-funnel.sh --off vaultwarden   # tailnet-only, temporarily
sudo ./tools/enable-funnel.sh vaultwarden         # and back
```

It runs the same guard and asks for a typed confirmation. `--off` leaves
`tailscale serve` alone, so tailnet access is unaffected — but the next
`deploy.sh` will publish again, because `serve.conf` still says `FUNNEL=yes`.
Change the declaration if you mean it permanently.

### What no script can check

**TOTP 2FA on both accounts** (enforced by Organization policy) and **Argon2id
KDF with raised iterations**. Do both in the web vault. They are the bulk of the
real protection and nothing here can verify them.

### Why tagging matters

A container is not a security boundary. A Vaultwarden compromise on an
untagged node would be a foothold on the whole tailnet. A tagged node is owned
by the tailnet rather than by you, so it is not in `autogroup:member` and gets
no outbound access to anything. Your phone reaches it; it reaches nothing.

Applying the tag **re-authenticates the machine**, which is why it happens at
join time in `bootstrap/30-access.sh` and not later: you are already
authenticating there, so it costs nothing, and the node is tagged before
anything is ever published from it.

Changing the tag on a host that is already up is a deliberate manual step —
`30-access.sh` warns about a mismatch but will not force a re-auth on you
mid-run. Do it from `tmux`, LAN ssh, or the console, not from the Tailscale SSH
session it is about to interrupt.

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
