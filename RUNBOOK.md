# RUNBOOK — fidelacchius

Operating notes for the host this repository provisions. Written for whoever
is reading it at 11pm with something broken, which may well be you having
forgotten all of it.

Current as of Phase 3: `bootstrap/` complete; Vaultwarden live and public via
Funnel; Immich, Mealie, Vikunja, Memos and Homepage on the tailnet;
nightly restic backups to B2. See
[Not done yet](#not-done-yet).

---

## The machine

| | |
|---|---|
| Host | `fidelacchius` — Intel i3-2120, 7.7 GiB RAM, legacy BIOS |
| OS | Arch Linux, `linux-lts` primary with mainline `linux` as fallback |
| Root | 50 GiB Btrfs on SSD label `archroot`, subvolume `@` |
| App state | ~61 GiB ext4 on SSD label `APPDATA` → `/opt/appdata` |
| Pool | mergerfs at `/mnt/pool` over `/mnt/disk1..3`, ~4.2 TiB usable |
| Parity | SnapRAID, one drive at `/mnt/parity1`, outside the pool |
| Access | sshd (keys only) on the LAN, Tailscale SSH over the tailnet |
| Repo | `/opt/stack` — a git checkout, the definition of this host |

Drives are identified by serial, never by `/dev/sdX`. The table is
[`drives.conf`](drives.conf) and it is read by the scripts, not kept as
documentation.

---

## Getting in

Three doors, in the order you should try them.

1. **SSH over the tailnet** — `ssh mbutler@fidelacchius`. Works from anywhere
   the tailnet reaches, including cellular.
2. **SSH over the LAN** — `ssh mbutler@<address>`. Keys only; passwords and
   root login are refused. Independent of Tailscale, which is the point: a
   tailnet outage does not cost you this, and a bad `sshd_config` does not
   cost you Tailscale.
3. **The console** — a monitor and keyboard on the machine itself. `mbutler`
   with the password set during install. **Root is locked**, deliberately, so
   this password is the only console credential. It is not needed for `sudo`
   (wheel is NOPASSWD) or for SSH (keys only) — it exists solely for this.

If all three fail: boot the Arch ISO and work from there, per
[`README.md`](README.md).

---

## The quarterly ritual

Roughly 45 minutes, four times a year. In order:

```bash
# 1. Read the news first. Arch announces manual interventions here, and they
#    are the only updates that will actually hurt you.
#    https://archlinux.org/news/

# 2. Keyring before anything else. A stale signing key is THE failure mode
#    for a host updated at long intervals.
sudo pacman -Sy archlinux-keyring

# 3. Update. paru, NOT pacman — see below.
paru -Syu

# 4. Reconcile config files the update wants to change.
sudo pacdiff

# 5. Reboot if the kernel moved. See "kernel updates" below — this is not
#    optional politeness, things break without it.
sudo reboot

# 6. Confirm nothing drifted.
cd /opt/stack && sudo ./tools/verify.sh
```

Then look at:

- `cd /opt/stack && sudo ./tools/check-image-pins.sh` — has upstream moved a
  pinned image past us? See [Pinned images](#pinned-images).
- `systemctl list-timers` — everything still scheduled?
- `df -h /` and `df -h /mnt/pool` — fill levels
- `journalctl -u podman-auto-update -n 50` — what has been updating itself
- `snapraid status`
- The SMART delta report (see [Drive health](#drive-health))

### `paru -Syu`, not `pacman -Syu`

**mergerfs and snapraid are AUR-only.** `pacman` does not update them, and
worse, they need *rebuilding* when a dependency's soname moves — a `fuse3`
bump can break the pool months after you stopped paying attention. `paru`
covers the repos and the AUR in one command.

Every other `pacman` habit still applies; `paru` passes them through.

### Kernel updates require a reboot before you trust anything

A `-Syu` that includes a kernel replaces the module tree on disk while the old
kernel keeps running. Anything that needs to load a module it has not already
loaded then fails — and it presents as a broken daemon, not as a pending
reboot.

**This has already bitten once here**: `tailscaled` could not get `/dev/net/tun`
and exited 1 with no useful message.

`run.sh` and `tools/verify.sh` both detect this state now and say so. The check
is whether `/usr/lib/modules/$(uname -r)` still exists.

### Snapshots make this safe

`snap-pac` brackets every pacman transaction with a pre/post snapshot pair.
If an update breaks the machine, reboot, pick the pre-update snapshot from the
GRUB **Advanced options → snapshots** submenu, and you are back where you
started in about two minutes.

---

## Alerts, and what each one means

All pushes go to ntfy on your phone. The topic lives in
`/etc/homelab/alerting.env` (mode 0600) — **the topic is the credential**;
anyone who knows it can read every alert and publish convincing fakes.

| Alert | What happened | What to do |
|---|---|---|
| `<unit> failed` | Any unit with `OnFailure=` died. The push includes the last 15 journal lines. | `journalctl -u <unit> -n 100` |
| `SMART — <device>` | smartd saw an attribute move, a failed self-test, or a temperature limit. | Read the message. Check the delta report before acting — see below. |
| `SMART counters moved` | The weekly snapshot found a watched counter changed. | This is the trend, not a single reading. Act on the rate. |
| `containers updated` | `podman auto-update` applied something. | Read it. Nothing to do unless something also failed. |
| `container auto-update FAILED` | The update run errored. | `journalctl -u podman-auto-update -n 100`. Containers are on their previous images. |
| `homelab-backup.service failed` | The nightly backup errored. **Nothing was uploaded.** | `journalctl -u homelab-backup -n 100`. Most likely: the pool unmounted, B2 credentials, or a database that would not dump. |
| `homelab-backup-check.service failed` | `restic check` found the repository damaged. | Do not prune. `journalctl -u homelab-backup-check -n 100`, then see [Backups](#backups). |
| Healthchecks: *check is down* | A timer stopped pinging. **Nothing on the host sent this** — the hosted service noticed silence. | The machine may be dead. Try the three doors above. |

The heartbeat is the only alert that fires by **absence**. Everything else
needs the host alive enough to notice its own problem; a dead host, a wedged
kernel or a cut power line cannot report anything.

---

## Storage

### Layout

```
/mnt/disk1  DISK1    ext4   ┐
/mnt/disk2  DISK2    ext4   ├─ mergerfs ─→ /mnt/pool
/mnt/disk3  DISK3    ext4   ┘
/mnt/parity1 PARITY1 ext4   ── SnapRAID parity, NOT in the pool
```

Everything is mounted by label with `nofail` and a 5-second device timeout, so
**a dead drive degrades the pool instead of dropping the host to an emergency
shell**. That matters: an emergency shell has no network and no ssh.

### The mountpoint lockdown

Each branch mountpoint is `chown root:root`, `chmod 0000`, `chattr +i` on the
*underlying* directory, applied before it was ever mounted.

This prevents a specific silent failure: a drive fails to mount, its mountpoint
is an ordinary empty directory on the root filesystem, and mergerfs adopts it as
a writable branch. Photos then land on the 50 GiB SSD while everything reports
the pool as healthy — until the SSD fills.

`/mnt/pool` itself is locked the same way for the same reason.

**Consequence when you are working by hand**: if you unmount a branch, the
directory underneath is unwritable and immutable. That is correct. To
deliberately change it: `chattr -i /mnt/diskN` first.

### fstab

Pool entries live in a marked block in `/etc/fstab`, generated from
`drives.conf` by `bootstrap/40-storage.sh`:

```
# >>> homelab pool mounts — generated from drives.conf by bootstrap/40-storage.sh
...
# <<< homelab pool mounts
```

**Do not delete one marker without the other.** The block replacement drops
everything between them; a missing end marker would drop everything from the
begin marker to end of file. The script refuses to run if only one marker is
present, and keeps a backup at `/etc/fstab.homelab.bak`.

Edits outside the block are preserved.

### When a pool drive dies

1. Do **not** run `snapraid sync`. Parity currently describes the array as it
   was, and that is what makes recovery possible. The wrapper will refuse
   anyway (see below), but do not fight it.
2. `cd /opt/stack && sudo ./tools/check-drives.sh` — confirms which serial is
   missing.
3. Fit the replacement, format and label it to match `drives.conf`. This is
   deliberately **not** scripted: `bootstrap/` never formats anything. See
   `tools/format-pool-drive.sh` (explicit arguments only).
4. Mount it, then `sudo snapraid fix -d dN -l /var/log/snapraid-fix.log`
   where `dN` is the failed drive's name from `/etc/snapraid.conf`.
5. Verify, then resume normal syncs.

If the replacement has a different serial, **update `drives.conf` and commit
it** — every script resolves through that table.

---

## SnapRAID

### What it is and is not

Parity is computed on a schedule, not continuously. Anything written since the
last sync is unprotected, and **a file deleted before a sync is gone for good
after that sync**. That trade buys per-drive independence: every drive holds an
ordinary ext4 filesystem readable in any machine, and losing two drives loses
only what was on those two.

### Schedule

| | |
|---|---|
| Sync | nightly 03:00 (±15m) via `snapraid-sync.timer` |
| Scrub | Sundays 04:30 (±30m), 12% of blocks older than 10 days |

Scrub walks the whole array roughly every two months, which catches bit rot
long before a drive failure makes it matter, and spreads the read load thin
enough not to hammer seven-year-old drives.

### The sync wrapper — read this before overriding it

The timer never calls `snapraid sync` directly. It calls
`/usr/local/bin/snapraid-sync`, which refuses in two cases:

**A data drive is not mounted.** SnapRAID has no idea a drive is missing. It
walks the mountpoint, finds an empty directory, concludes every file was
deleted, and updates parity to match. Those files become unrecoverable. Running
as root it is not even stopped by the `chmod 0000` lockdown — root ignores it.
This is the most destructive thing that can happen to the array without anyone
touching a disk, and without the wrapper it would happen on a timer, at night.

**More than 500 files disappeared.** Same failure, subtler causes: a filesystem
that mounted read-only, a half-finished restore, a bad `rm`. SnapRAID ships no
threshold upstream.

To override for a genuine mass deletion:

```bash
sudo SNAPRAID_FORCE=1 /usr/local/bin/snapraid-sync
```

Before you do: parity still describes the array as it was. If the deletion was
not intentional, that is what recovery depends on.

### Useful commands

```bash
sudo snapraid status                    # array state, last scrub age
sudo snapraid diff                      # what would change on the next sync
sudo /usr/local/bin/snapraid-sync       # sync, with the guards
sudo snapraid scrub -p 12 -o 10         # what the weekly timer runs
sudo snapraid check                     # verify without repairing
sudo snapraid fix -d d2                 # rebuild drive d2 from parity
```

---

## Snapshots

Snapper on `/`, snapshots in `@snapshots` — a first-class subvolume **outside**
`@`, so rolling back the root subvolume does not take the other snapshots with
it.

Timeline snapshots are **off**. On a host updated quarterly, whose root barely
changes outside a pacman transaction, hourly snapshots are thousands of
near-identical copies carrying no information. `snap-pac`'s pre/post pairs are
the ones worth keeping. Retention: 12 numbered, 8 important.

```bash
sudo snapper -c root list               # what exists
sudo snapper -c root status 41..42      # what changed between two
sudo snapper -c root undochange 41..42  # revert those file changes, no reboot
```

`undochange` handles anything that is not the kernel. A kernel rollback needs a
reboot into the snapshot, because you are booting that snapshot's initramfs.

**Booting a snapshot**: reboot, GRUB menu → *Advanced options for Arch Linux* →
*snapshots*. `grub-btrfsd` keeps that submenu current automatically.

> `grub-btrfsd` needs `inotify-tools`, which is only an *optional* dependency of
> `grub-btrfs`. Without it the daemon exits 1 immediately and snapshots never
> reach the boot menu, while `systemctl is-enabled` still says "enabled".
> `bootstrap/20` installs it and `verify.sh` checks `is-active`, not
> `is-enabled`.

---

## Drive health

### The baseline

`docs/smart-baseline-2026-08-27.md` records every drive's SMART attributes as
of pre-provisioning. It is the zero point every later reading is measured from.

`/usr/local/bin/smart-snapshot` runs weekly (Mondays 07:00), writes full
`smartctl -A` output per drive to `/var/lib/smart-history/<timestamp>/`, and
reports any watched counter that moved — against both the previous snapshot and
the oldest retained one.

History is kept **forever**. The files are a few kilobytes and their entire
value is a long baseline.

### The open question: `Z4Z972VW`

That drive reads `UDMA_CRC_Error_Count = 137,840`.

- It is a **link** counter, not a media one. Every media attribute on that
  drive is zero. The platters are fine.
- It is **cumulative over the drive's life** — 60,829 power-on hours across
  many different cables, controllers and enclosures. A six-figure count is
  equally consistent with a problem that closed years ago and one happening
  now. The magnitude cannot distinguish them; only the rate can.
- `PASSED` means nothing here. Seagate normalises attribute 199 to 200 against
  a threshold of 0, so it never trips overall health at any raw value.

**What to do**: read the weekly delta reports. If the count is static across
several weeks of nightly syncs and weekly scrubs — real traffic on that link —
close the item. If it is climbing, isolate one change at a time: cable first
(cheapest and most likely), then a different port on the add-on card, then
suspect the drive's own SATA interface. Changing several things at once
destroys the evidence of which was at fault.

Deliberately **not** blocking anything. `Z4Z972VW` is a data member, not
parity — SnapRAID writes parity on every sync and only reads data drives on
scrub, so the write-heaviest role is on a drive with a clean link.

---

## Containers

Rootful Podman, Quadlet units, no daemon. `systemctl` and `journalctl` are the
management interface.

**Every `podman` command here needs `sudo`.** Rootless and rootful Podman keep
entirely separate container and image stores, so a bare `podman ps` as your own
user reports an empty machine while every service is running normally — it is
looking at your store, which is empty and always will be. This is the single
most confusing thing about the setup:

```bash
sudo podman ps                      # what is actually running
sudo podman exec vaultwarden printenv | grep -i signups
sudo podman images
```

```
/etc/containers/systemd/     Quadlet units (symlinks into /opt/stack/apps/)
/opt/appdata/<app>/          application state, ext4, NOT snapshot-rolled-back
/mnt/pool/<...>              bulk data, on the pool
/var/lib/containers          image store, its own Btrfs subvolume
```

`/var/lib/containers` is a separate subvolume so image layers are not captured
by every root snapshot. `bootstrap/70` refuses to run if either that or
`/opt/appdata` is not a separate mount.

### Every app unit needs both of these

```ini
RequiresMountsFor=/opt/appdata /mnt/pool
```
A failed mount stops the service instead of being written around.

```ini
Label=io.containers.autoupdate=registry
```
Without it the container never updates — and the tag it tracks **is** the
update policy.

### Auto-updates

Daily at 05:00 (±30m), through `/usr/local/bin/podman-auto-update-run`. Quiet
when nothing changed, pushes when something did. On failure it pushes *and*
skips the Healthchecks ping, so the dead-man switch reports it even if the push
did not get out.

Podman rolls back to the previous image automatically if an updated service
fails to come up.

Images are pruned weekly (Sundays 06:00) — every update leaves the old image
behind and they would fill the root filesystem over months.

`podman.socket` is enabled, and **exactly one thing consumes it**: the
whitelisting proxy that Homepage reads through.

Access to that socket is equivalent to root on this host — the API can create a
container, bind-mount `/` into it and run anything. Mounting it `:ro` does not
help: read-only applies to the socket *file*, while every dangerous verb in the
API is a POST. So no container gets the socket. `homepage-socket-proxy` allows
`CONTAINERS=1` and 403s everything else, and is not published to the host at
all — it exists only on the `homepage` network.

---

## Pinned images

Most containers carry `AutoUpdate=registry` and are updated by the daily
`podman-auto-update` timer. **Immich's database is pinned to an exact tag**, and
the tag is doing real work:

```
ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0
```

It names the PostgreSQL major *and* both extension versions, so auto-update can
only ever deliver a rebuild of that same combination — a patched 14.x with the
same extensions, needing no migration. That is precisely what makes
`AutoUpdate=registry` safe to leave on it.

What the pin prevents is an update that **needs a step an image swap cannot
perform**:

- A **PostgreSQL major** bump changes the on-disk format. The new binary
  refuses to start against the old data directory — it fails closed rather than
  corrupting anything, but the service is down until you run `pg_upgrade` or a
  dump/restore. Postgres does not downgrade.
- A **VectorChord** bump needs SQL afterwards:
  ```sql
  ALTER EXTENSION vchord UPDATE;
  REINDEX INDEX face_index;
  REINDEX INDEX clip_index;
  ```
  Skip it and the database starts, serves, and has stale indexes — nothing
  complains, which is the worst shape of failure.

Immich supports PostgreSQL 14 through 19, so a pinned 14 will not be outrun by
server updates for years. But a pin nobody watches is just a stale version, so:

```bash
sudo ./tools/check-image-pins.sh          # compares our pin to Immich's current release
sudo ./tools/check-image-pins.sh --notify # ... and pushes if it has drifted
```

It changes nothing. When it reports drift, that is a deliberate maintenance
task: read the release notes, snapshot, move the tag, run the migration.

---

## Applications

Deployed with `deploy.sh`, which **symlinks** unit files from `apps/<name>/`
into `/etc/containers/systemd/`. Nothing is copied, so there is never a
deployed unit that has drifted from the repository — `git pull` then
`systemctl restart <app>` is the whole update path.

```bash
cd /opt/stack
sudo ./deploy.sh                # every app
sudo ./deploy.sh vaultwarden    # one
sudo ./deploy.sh --list         # what is linked, and to what
sudo ./deploy.sh --remove NAME  # unlink; does not stop or delete anything
```

`deploy.sh` starts what it deploys: it starts anything not running, and
restarts anything whose unit file changed. Boot-time startup needs no
`systemctl enable` — Quadlet honours the `[Install]` section inside each
`.container`. Use `--no-start` to link and reload without touching services.

**`/etc/homelab/repo`** is a symlink to this checkout, maintained by
`deploy.sh`. Quadlet units cannot substitute variables, so a unit that
bind-mounts something out of the repository (Homepage's config) names that
stable path rather than hardcoding one clone's location.

**Secrets** live in `apps/<name>/<name>.env` — in the repo, gitignored, next to
the unit that consumes them — and are symlinked into `/etc/homelab/apps/`, so
every secret on this host is discoverable in one directory.

Same contract as `host.conf`: the repo ships `<name>.env.example`, you copy it
and fill it in. `deploy.sh` stops with the exact commands if one is missing,
and handles ownership, 0600 and the symlink itself once it exists.

Those files are not in git and not recoverable from the vault they configure.
**Keep copies in your password manager.**

| App | Reachable at | State | Notes |
|---|---|---|---|
| Vaultwarden | `:443` (**public**, Funnel) | `/opt/appdata/vaultwarden` | [README](apps/vaultwarden/README.md) |
| Immich | `:8444` tailnet only | `/opt/appdata/immich` + `/mnt/pool/photos` | [README](apps/immich/README.md) |
| Mealie | `:8445` tailnet only | `/opt/appdata/mealie` | [README](apps/mealie/README.md) |
| Vikunja | `:8446` tailnet only | `/opt/appdata/vikunja` | [README](apps/vikunja/README.md) |
| Memos | `:8447` tailnet only | `/opt/appdata/memos` | [README](apps/memos/README.md) |
| Homepage | `:8448` tailnet only | `apps/homepage/config/` — in git | [README](apps/homepage/README.md) |

Each app's state and how it must be captured for backup is recorded in
[`docs/backup-inventory.md`](docs/backup-inventory.md) as it is deployed.

**Vaultwarden stays on SQLite even though Immich brings a Postgres.** Sharing
one would couple the password manager's availability to a photo app's database
and its upgrade schedule — and Vaultwarden is what holds the credentials you
need to fix everything else. Any future app needing Postgres gets its own
instance for the same reason.

Start at Homepage — `:8448` links to all of them and shows what is running.

**One app per port, and 443 is Vaultwarden's alone.** Funnel is enabled per
port, not per path, so anything sharing a port with a funnelled app goes public
with it. Tailscale only funnels 443, 8443 and 10000 — so every tailnet-only app
here is given a port *outside* that set, and `lib/publish.sh` refuses a
`serve.conf` that contradicts itself either way.

### Reachability is part of deploying

Containers bind `127.0.0.1` and nothing else. What makes them reachable is
`tailscale serve`, and that state lives in tailscaled — **it does not survive a
rebuild.** So it is not a manual step. Each app declares it:

```
apps/<name>/serve.conf
    SERVE_TARGET=http://127.0.0.1:8222   what to forward to
    SERVE_PATH=/                         mount point on 443
    FUNNEL=yes                           also expose to the public internet
    FUNNEL_GUARD=funnel-guard.sh         veto script, run before opening the port
```

`deploy.sh` converges the machine to match, every run, after confirming the
service is up. `--no-publish` skips it. `lib/publish.sh` is the implementation.

Two pieces of state this host depends on and cannot create, applied once in the
Tailscale admin console and surviving every rebuild:

1. **DNS → HTTPS Certificates**, enabled. Without it nothing serves over TLS.
   `deploy.sh` stops with this instruction rather than a confusing cert error.
2. **Access Controls**, the policy from `apps/vaultwarden/tailnet-policy.hujson`
   — `tagOwners` for `tag:server` plus the `funnel` node attribute.

The node claims that tag at join time from `TAILSCALE_TAGS` in `host.conf`,
because advertising a tag re-authenticates the machine and join is the one
moment that costs nothing.

### The one public service

Vaultwarden is the only thing reachable from outside the tailnet. Funnel is
enabled per **port**, not per path, so 443 stays exclusively Vaultwarden:
anything else ever mounted there becomes public with it. Other apps get a
different `tailscale serve` port.

Before opening the port, `deploy.sh` runs `apps/vaultwarden/funnel-guard.sh`,
which vetoes on: `SIGNUPS_ALLOWED=true`, `ADMIN_TOKEN` set, or `DOMAIN` not
matching this node's MagicDNS name. A veto is **not a deploy failure** — the
tailnet mount still goes up, only the public door waits, and the next deploy
after you fix the cause opens it.

`tools/enable-funnel.sh` is the manual path for what is not a deploy:

```bash
sudo ./tools/enable-funnel.sh --off vaultwarden   # tailnet-only, temporarily
sudo ./tools/enable-funnel.sh vaultwarden         # and back
```

`--off` leaves `tailscale serve` alone, so tailnet access is unaffected. The
next `deploy.sh` republishes, because `serve.conf` still says `FUNNEL=yes`.

Adding a user means opening registration, and with Funnel live that window is
open to the internet rather than the tailnet. Minutes, not days. The procedure,
and the safer variant for someone who is already on the tailnet, are in
[apps/vaultwarden/README.md](apps/vaultwarden/README.md#adding-someone-later).

A port scan of the home IP will not show any of this — Funnel is an outbound
tunnel and never touches the router. A clean scan is not evidence that
Vaultwarden is private.

---

## Backups

`restic` to Backblaze B2, nightly at 02:30, plus a weekly repository
verification on Saturdays at 04:00. What is captured and *how* is specified in
[`docs/backup-inventory.md`](docs/backup-inventory.md); `homelab-backup`
implements it.

```bash
sudo systemctl start homelab-backup.service    # run one now
journalctl -u homelab-backup -f
sudo systemctl list-timers 'homelab-backup*'

set -a; . /etc/homelab/backup.env; set +a      # then restic directly:
restic snapshots
restic stats latest
```

### The rule the whole script is built around

**A running database cannot be backed up by copying its files.** Every database
is dumped first — SQLite via `.backup`, Immich's Postgres via `pg_dump` inside
the container — and the **live database files are excluded from the snapshot**.
The repository never contains a torn copy sitting next to a good one, because
that is how you restore the wrong one at 2am. Dumps carry a `.dump` suffix so
the exclusions cannot swallow them, and each SQLite dump is opened and
`integrity_check`ed before it is allowed into the repository.

### The refusals

- **`/mnt/pool` not mounted** → refuses. Backing up an absent photo library
  writes an empty snapshot, and retention then prunes the good ones away behind
  it. That is how a backup system deletes your data.
- **Repository unreachable** → refuses rather than continuing silently.
- **A dump that fails `integrity_check`** → refuses.

### What restic does NOT follow

`/etc/homelab/apps/*.env` are symlinks into the repository, and **restic stores
a symlink as a symlink**. Backing up that directory would archive a set of
pointers. So `host.conf` and every app `.env` are copied into the staging
directory as real files first. Those are the files that make a restored machine
*this* machine — they are gitignored, so nothing else carries them.

### The first run is the big one

It uploads the entire photo library. On a domestic upstream that is measured in
nights, not hours — and while it runs, an uncapped restic will saturate the
connection and take the rest of the house's internet with it.

Set `RESTIC_LIMIT_UPLOAD` in `host.conf` (KiB/s; roughly 60% of measured
upstream, so 1250 is about 10 Mbit/s) and re-run `./run.sh --only 80`.

A run killed by the 12-hour timeout is **not wasted**: restic re-uses whatever
already reached the repository, so the next night continues from where the data
ends. systemd will not start a second instance while one is running, so a long
job skips the next night rather than overlapping. Expect the first few nights to
fail on timeout and the alerts to stop once it catches up.

```bash
restic stats latest              # what is actually up there
restic snapshots                 # and when
```

### Retention and cost

7 daily, 5 weekly, 12 monthly. `forget` runs every night; `prune` only on
Sundays, because prune rewrites pack files and is the expensive operation in
both wall clock and B2 transactions.

### The key

`RESTIC_PASSWORD` in `host.conf` is the encryption key for the entire
repository. **There is no recovery without it, by design.** It must live
somewhere reachable when Vaultwarden is the thing that is down.

### If `restic check` reports damage

Do not prune — prune rewrites the pack files that `check` just told you it
cannot trust. Read the failure, then:

```bash
restic check --read-data          # full verification, downloads everything
restic repair snapshots           # drops snapshots referencing lost data
```

A repository that has lost data is not automatically worthless: older snapshots
usually survive. Establish what is intact before deleting anything.

---

## Verification

```bash
cd /opt/stack
sudo ./tools/verify.sh        # the full acceptance checklist
sudo ./tools/check-drives.sh  # just the drive table
```

`verify.sh` is read-only and safe any time. Three outcomes: `ok`, `FAIL`, and
`--` for a stage that has not been run. A failing check prints what it tested
and what it saw, so it explains itself rather than sending you hunting.

Exit status is non-zero only on a real failure, so it works as a gate.

---

## Rebuilding from scratch

Full sequence in [`README.md`](README.md). The two things that are not in git:

1. **`host.conf`** — gitignored. The real copy lives in your password manager.
   A rebuild restores the repository but not this machine's identity.
2. **Tailscale node identity** — the machine re-authenticates and gets a new
   node. Remove the stale one from the admin console.

Everything else — partition layout, package set, configuration, timers,
alerting — comes from this repository.

---

## Gotchas discovered building this

Recorded because each one cost real time and none of them are obvious.

- **`pacman -Syu` + kernel = reboot before trusting daemons.** See above.
- **`grub-btrfsd` needs `inotify-tools`**, an optional dependency. Dies
  instantly without it while still reporting "enabled".
- **fstab fstype for the pool is `mergerfs`, not `fuse.mergerfs`.** util-linux
  resolves `fuse.X` through `/sbin/mount.fuse`, which fuse2 shipped and fuse3
  does not. Without it, options go to the kernel fuse driver, which rejects
  them: `fuse: Unknown parameter 'cache.files'`.
- **`snapper create-config` fights a pre-existing `.snapshots`.** `bootstrap/20`
  unmounts, lets snapper create its own, deletes it, and remounts ours.
- **`arch-chroot` bind-mounts the host's `/etc/resolv.conf` into the target.**
  Anything done to that path from inside the chroot acts on the live ISO's
  file. `install/03` writes both symlinks from outside instead.
- **`cmd | grep -q` under `set -o pipefail` is a trap.** grep exits at the
  first match, the producer dies on SIGPIPE (141), and pipefail reports failure
  *because the match succeeded*. It passes on short output and fails on long.
  Use `grep_output` from `lib/common.sh`.
- **`sshd -T` capitalises keywords** on current OpenSSH. Match
  case-insensitively.
- **`sshd -t` proves the file parses, not that it is read.** A drop-in that is
  never included parses perfectly. Assert the effective config.
- **The fstype findmnt REPORTS for mergerfs is not stable.** It has been
  `fuse.mergerfs` and it has been plain `mergerfs`; an upgrade flipping it
  failed a healthy pool in `40-storage.sh`. Match `(fuse\.)?mergerfs`, and in
  general assert what a mount *is*, not what a version labels it. (The fstab
  fstype above is a separate thing and must stay `mergerfs`.)
- **Tags are set with `tailscale login`, not `tailscale set`.** `set` has no
  `--advertise-tags` flag: a tag changes who *owns* the node, so it needs a
  re-authentication rather than a preference change. `tailscale up
  --advertise-tags=... --force-reauth` also works but wants every other pref
  restated to avoid resetting them.
- **tmpfiles.d must not manage a directory a container owns.** A `d` line
  re-applies mode and ownership on every `systemd-tmpfiles --create` — at boot
  and whenever `deploy.sh` touches a tmpfiles file. Postgres chowns its data
  directory to itself on first start, so a root-owned line took it back after
  it was already working. The running postmaster kept serving from open file
  descriptors, so Immich looked fine, while every new backend died with
  `FATAL: could not open file "global/pg_filenode.map": Permission denied` —
  discovered weeks later by a backup at 02:30. Directories a container takes
  ownership of are created by `mkdir` in an `ExecStartPre` and never chowned.
- **A container that dropped privileges cannot write a root-owned volume.**
  State directories are owned to match the uid the image runs as, per app, in
  `system/tmpfiles/`. Vikunja (uid 1000, no `PUID` support) failed this way and
  the log said only `config file not found, using defaults` — which is normal
  output and not the error. Look past the first complaint to the fatal one.
- **Podman will not create a bind-mount source directory.** It fails with
  `statfs <path>: no such file or directory` rather than doing what `docker run`
  trained you to expect. For a path on the pool the directory cannot come from
  tmpfiles.d either — that runs before the pool is mounted and would create it
  on the SSD — so it is an `ExecStartPre` in the unit, after
  `RequiresMountsFor` has guaranteed the mount.
- **Removing a unit from an app used to leave it running.** `deploy.sh` linked
  units but never unlinked one that went away, so moving a component out of an
  app directory left the symlink, and Quadlet kept generating and starting the
  service. The repository said gone, the machine said running. It now prunes
  links pointing into an app directory that no longer match a file there.
- **A container can outlive its unit, and then nothing manages it.** Removing a
  Quadlet unit and reloading leaves systemd with nothing to stop while podman
  keeps the container running — invisible to `systemctl`, absent from the
  repository, still holding its ports. `deploy.sh` stops the service *and*
  then the container when it prunes. To find strays by hand, compare
  `sudo podman ps` against `systemctl list-units 'immich*'`.
- **`podman ps` without sudo shows nothing, and that is not an error.** Rootless
  and rootful Podman have separate stores. Your user's store is empty; the
  services live in root's. Every `podman` command in this runbook needs `sudo`.
- **Editing an app's `.env` does nothing until the container restarts.**
  systemd reads `EnvironmentFile` at start and never again, and `deploy.sh`
  used to report "already running, unit unchanged" because only the *unit* was
  tracked. A setting looked applied while the old value stayed live — which for
  `SIGNUPS_ALLOWED` meant an open registration page on a vault believed closed.
  `deploy.sh` now restarts when the env file is newer than the service's
  `ActiveEnterTimestamp`.
- **A precondition that discards the error it is checking for is worse than no
  precondition.** `homelab-backup` ran `restic snapshots >/dev/null 2>&1` and
  reported a flat "cannot reach the repository" while the repository existed
  and worked by hand. The reason was thrown away with the stderr. It now prints
  restic's own complaint before dying.
- **A systemd service inherits almost no environment.** No `HOME` for a service
  with no `User=`, so anything that wants a cache or config directory has to be
  told where. Both backup units set `RESTIC_CACHE_DIR` explicitly and let
  `CacheDirectory=` create it — "works in my shell, fails as a unit" is nearly
  always this.
- **A guard that reads a config file is checking a claim, not a fact.** The
  funnel guard read `vaultwarden.env`, which said `SIGNUPS_ALLOWED=false` while
  the running container had `true` — it would have published an open
  registration page to the internet while reporting registration shut. It now
  reads `podman exec vaultwarden printenv` and reports drift between the two.
  Third instance of this shape, after `sshd -t` and the mergerfs fstype: **ask
  the running thing what it believes.**
- **Vaultwarden's `config.json` beats the environment.** Anything saved from
  the admin page is persisted to `config.json` in the data directory and takes
  priority, so the env file stops being the truth. The funnel guard refuses to
  vouch for anything if that file exists.
- **`findmnt <target>` prints one line PER MOUNT at that target.** Capturing it
  into a scalar gives a multi-line string that fails every comparison, and the
  error message then splatters the extra lines across the log. Use `-f`
  (first-only), or `mapfile` when the count matters.
- **`mount -a` restacked the pool on every run.** It decides "already mounted"
  by source *and* target; fstab's source for the pool is the branch list while
  mergerfs reports `fsname=`, so they never matched and it mounted again each
  time — four deep before anything caught it. `40-storage.sh` now runs
  `mount -a -t nomergerfs` and mounts the pool by target.
- **`nofail` hides mount failures from `mount -a`.** It exits 0 having skipped
  the entry. Correct for boot — a dead drive should not strand the host — but
  it means a check after `mount -a` must re-attempt the mount to see the error,
  not just assert and give up.
- **Vaultwarden's `DATABASE_URL` needs a scheme.** A bare path is not a URL;
  it must be `sqlite:///data/db.sqlite3` — three slashes, `sqlite://` plus the
  absolute path. Without it the container exits at startup rather than falling
  back to a default. Fixed in `vaultwarden.env.example`.
- **A container listening on `127.0.0.1` is reachable from nowhere until
  `tailscale serve` is up.** The loopback bind is deliberate, but it means
  "the service is running" and "I can load the page" are two separate
  problems. Check `tailscale serve status` before debugging the app.

---

## Not done yet

- **Failure drills.** None of these have been performed. Do them before the
  pool holds anything: pull a drive and confirm degraded boot + refusals;
  swap two labels in `drives.conf` and confirm `40` refuses; stop
  `homelab-heartbeat.timer` and confirm the dead-man switch alerts; boot a
  snapshot and return cleanly.
- **A restore that has actually been performed.** The backups run, but a
  backup nobody has restored is a hypothesis, not a backup. The drill is at the
  end of [`docs/backup-inventory.md`](docs/backup-inventory.md) and belongs in
  Phase 5, before the failure drills.
  Add to that file when you add an app — the per-app "how" (`.backup`,
  `pg_dump`, plain copy) is easy to know now and expensive to reconstruct.
- **Applications.** Phase 3. Vaultwarden, Immich, Mealie, Vikunja, Memos and
  Homepage are deployed. Still to come: Home Assistant and Z-Wave JS UI (3d),
  the
  Frigate (deferred to Stage 2, with the cameras).
- **File Browser: dropped, deliberately.** It was archived 2026-09-01 with the
  maintainer telling users to treat it as unmaintained. Ad-hoc file access is
  SFTP over Tailscale SSH, which already exists and adds no attack surface. If
  a Dropbox-style *sync* need appears later, that is Syncthing, not a web file
  manager — see [Goodbye File Browser](https://hacdias.com/2026/07/28/filebrowser/).
- **Camera footage and SnapRAID.** Currently *inside* parity protection,
  reversing the original plan. Revisit when cameras are actually bought.
- **`Z4Z972VW`.** Watching. See [Drive health](#drive-health).
