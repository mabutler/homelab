# RUNBOOK — fidelacchius

Operating notes for the host this repository provisions. Written for whoever
is reading it at 11pm with something broken, which may well be you having
forgotten all of it.

Current as of the completion of `bootstrap/`. Applications are not yet
deployed; see [Not done yet](#not-done-yet).

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

`podman.socket` is enabled but **nothing consumes it yet**. Access to that
socket is equivalent to root on this host; when Homepage arrives it gets a
read-only proxy in front of it, never the socket itself.

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

**Secrets** live in `apps/<name>/<name>.env` — in the repo, gitignored, next to
the unit that consumes them — and are symlinked into `/etc/homelab/apps/`, so
every secret on this host is discoverable in one directory.

Same contract as `host.conf`: the repo ships `<name>.env.example`, you copy it
and fill it in. `deploy.sh` stops with the exact commands if one is missing,
and handles ownership, 0600 and the symlink itself once it exists.

Those files are not in git and not recoverable from the vault they configure.
**Keep copies in your password manager.**

| App | State | Notes |
|---|---|---|
| Vaultwarden | `/opt/appdata/vaultwarden` | [apps/vaultwarden/README.md](apps/vaultwarden/README.md) |

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
- **Backups.** Phase 4. Nothing is backed up off this machine. SnapRAID is
  not a backup — it protects against drive failure, not against deletion,
  corruption, fire or theft.
- **Applications.** Phase 3, starting with Vaultwarden.
- **Tailscale ACLs and `tag:server`.** Policy written and committed at
  `apps/vaultwarden/tailnet-policy.hujson`, applied by `tools/enable-funnel.sh`
  — but only once you paste the policy into the admin console. Until then the
  tailnet runs the default allow-all, which is fine while nothing is public.
- **Read-only proxy for `podman.socket`.** Arrives with Homepage.
- **Camera footage and SnapRAID.** Currently *inside* parity protection,
  reversing the original plan. Revisit when cameras are actually bought.
- **`Z4Z972VW`.** Watching. See [Drive health](#drive-health).
