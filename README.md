# homelab

Scripted provisioning for an Arch Linux home server, from bare metal: partition
and install the OS, configure storage, stand up monitoring and alerting —
reproducibly, from a fresh Arch ISO, in one sitting.

Plain bash. No configuration-management framework. Arch Linux only. Written to
provision more than one machine: **a second host is a second `host.conf`, not a
second repository.**

Cloned to `/opt/stack` on each host it provisions.

---

## Status

| Stage | | |
|---|---|---|
| **A** | Scaffolding — `lib/common.sh`, config files, `run.sh` | **done** |
| B | `install/` — preflight, partition, pacstrap, chroot | not started |
| C | `bootstrap/` — `10` through `70` | not started |
| D | `tools/verify.sh` — the acceptance checklist as assertions | not started |
| E | `apps/` — Podman Quadlet units | separate scope |

Target host `fidelacchius`: Intel i3-2120, 7.7 GiB RAM, legacy BIOS.
One 120 GB SSD, three 2 TB and one 1 TB spinning drives.
See [`docs/smart-baseline-2026-08-27.md`](docs/smart-baseline-2026-08-27.md)
for the drive facts this repository was configured from, and for the pre-build
SMART zero point — including an open counter on `Z4Z972VW` that the first two
weeks of `smartd` and `tools/smart-snapshot.sh` output are expected to resolve.

---

## The two inputs

Everything machine-specific lives in exactly two files.

**`host.conf`** — hostname, admin user, timezone, ntfy topic, Healthchecks
URLs. Gitignored; copy `host.conf.example` and fill it in.

> Store the real `host.conf` in your password manager. A rebuild can restore
> this repository, but not this machine's identity.

**`drives.conf`** — the serial → label → role table. Read by the scripts
rather than kept as documentation, so it cannot drift from reality.

Serials are the only stable identity a drive has here: this machine has a SATA
add-on card and an external drive tower, and device letters shuffle between
boots. Every destructive or verifying operation resolves a serial through
`/dev/disk/by-id/`. **No script accepts a `/dev/sdX` path.**

---

## Layout

```
homelab/
├── host.conf.example       committed
├── host.conf               GITIGNORED — the only per-machine file
├── drives.conf             committed — serial → label → role
├── lib/common.sh           logging, guards, config loading, install helpers
├── install/                run from the live ISO. destructive. once.
├── bootstrap/              run on the installed system. idempotent.
├── files/                  everything that becomes host configuration
├── apps/                   container units (later stage)
├── tools/                  verify.sh, smart-snapshot.sh, format-pool-drive.sh
├── docs/
├── deploy.sh               symlink app units and tmpfiles, daemon-reload
└── run.sh                  runs bootstrap/ in order
```

---

## Conventions

1. **Configuration lives in `files/` and is installed with `install -Dm644`.**
   Scripts do not write config with heredocs. A file in the tree is diffable
   and greppable; a heredoc is neither. Use `install_file`, or
   `install_template` when a value from `host.conf` has to be substituted.
2. **`install/` is destructive and runs once. `bootstrap/` is idempotent and
   re-runnable.** Running `run.sh` twice produces no changes on the second pass
   — and, at default verbosity, almost no output. That silence is the test.
3. **Nothing in `bootstrap/` ever writes to a pool drive.** The scripts verify
   that drives match `drives.conf` and refuse to proceed on a mismatch. They
   never format, relabel, or repair. Provisioning a replacement drive is a
   documented manual procedure plus an explicit-argument tool.
4. **Every script sources `lib/common.sh`**, which applies `set -euo pipefail`
   and loads its own config — scripts are runnable individually, not only
   through `run.sh`.
5. **Templating is a single substitution pass over a fixed key list.** No
   template engine. An unsubstituted `@PLACEHOLDER@` is a hard error rather
   than something that silently ships into a config file.
6. **One commit per working script**, with its test result in the message.

---

## Install sequence

Physical access is needed only to insert the USB stick and reach a console
once.

1. Boot the Arch ISO. Set a root password, note the address, continue over SSH
   from a laptop. A DHCP reservation for the NIC keeps the address stable
   across repeated runs.
2. `pacman -Sy git`; clone this repository to `/root/stack`.
3. Place `host.conf`; confirm `drives.conf` matches
   `lsblk -d -o PATH,SIZE,ROTA,MODEL,SERIAL`.
4. `install/00-preflight.sh` — reports firmware mode and TRIM support,
   resolves every serial to a device, prints the exact device it will destroy,
   and waits for typed confirmation.
5. `install/01-partition.sh`, `02-pacstrap.sh`, `03-chroot.sh`. The repository
   is copied into the target at `/opt/stack` with `.git` intact. The user, SSH
   key and sshd are configured so the first boot is reachable without a
   keyboard. `03` does not reboot; it prints the next command and exits.
6. Reboot, remove the USB, SSH back in.
7. `cd /opt/stack && sudo ./run.sh`
8. `tailscale up --ssh`, authenticate, verify from an off-network device.
9. `tools/verify.sh`

---

## `run.sh`

```
./run.sh                 all bootstrap steps, in order
./run.sh --list          show the steps and exit
./run.sh --only 40,50    just these
./run.sh --from 30       this one and everything after
./run.sh --dry-run       print what would change, change nothing
./run.sh -v              report no-op steps as well as changes
```

`--dry-run` is meaningful for `bootstrap/` only. `install/` scripts do not
honour it: a dry run of a partitioning script cannot report what the step
after it would have found, and a flag that appears to work but doesn't is
worse than no flag.

---

## Target state

**SSD** (legacy BIOS, so GPT with a BIOS boot partition and `/boot` as a
directory inside the root subvolume):

| Partition | Size | Type | Filesystem | Label | Mount |
|---|---|---|---|---|---|
| p1 | 1 MiB | BIOS boot (`ef02`) | — | — | — |
| p2 | 50 GiB | Linux filesystem | Btrfs | `archroot` | `/` |
| p3 | ~61.8 GiB | Linux filesystem | ext4 | `APPDATA` | `/opt/appdata` |

`00-preflight.sh` detects firmware mode from `/sys/firmware/efi` and
`01-partition.sh` branches on it, so a future UEFI host gets a 1 GiB FAT32 ESP
at `/boot` in place of p1 without editing the scripts.

Btrfs subvolumes on p2: `@` → `/`, `@home`, `@var_log`, `@containers` →
`/var/lib/containers`, `@snapshots` → `/.snapshots`. Mounted
`noatime,compress=zstd:3`. Kernels live inside `@`, so a snapshot rollback
restores a matching kernel and initramfs.

Application state lives on ext4, not Btrfs: databases perform badly under
copy-on-write, and app state should not be rewound by an OS snapshot rollback.
p3 takes the full remainder — the SSD reports TRIM support, so no
overprovisioning gap is reserved.

**Pool**: mergerfs at `/mnt/pool` over `/mnt/disk1`–`/mnt/disk3`, with parity
at `/mnt/parity1` outside the pool. SnapRAID gives single-drive-failure
protection. All mounts are by label with `nofail` and a short device timeout,
so a dead drive degrades the pool instead of dropping the host to an emergency
shell. Branch mountpoints are locked (`chmod 0000`, `chattr +i`) before first
mount, so an unmounted drive cannot silently present an empty
root-filesystem directory as a writable pool branch.

**OS**: `linux-lts` primary with mainline `linux` as a fallback boot entry.
GRUB with `snapper` + `snap-pac` + `grub-btrfs`, so every package transaction
is bracketed by bootable snapshots. zram swap, journald capped at 1 GiB,
minimal package set, nothing that builds kernel modules.

**Access**: sshd keys-only with no root login and no password auth; Tailscale
with `--ssh` as an independent second path to a shell. Nothing forwarded at
the router.

**Monitoring**: `smartd` on all five drives with persistent state files —
without them smartd re-baselines on every restart and will not report a change
that happened across a reboot. Push notifications via ntfy for unit failures,
SMART attribute movement, and SnapRAID sync/scrub results. An hourly heartbeat
and per-timer success pings to a hosted dead-man service, so a timer that
silently stops firing is caught by absence.
