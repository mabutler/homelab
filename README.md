# homelab

Scripted provisioning for an Arch Linux home server, from bare metal: partition
and install the OS, configure storage, stand up monitoring and alerting.

Plain bash. No configuration-management framework. 

---

## Inputs

**`host.conf`** — hostname, admin user, timezone, ntfy topic, Healthchecks
URLs. Gitignored; copy `host.conf.example` and fill it in.

> Store the real `host.conf` securely. A rebuild can restore
> this repository, but not this machine's identity.

**`drives.conf`** — which drives are used for which purpose

Serials are the only identifier used by these scripts.

---

## Conventions

1. **Configuration lives in `files/` and is installed with `install -Dm644`.**
2. **`install/` is destructive and runs once. `bootstrap/` is idempotent and
   re-runnable.**
3. **Nothing in `bootstrap/` ever writes to a pool drive.**
4. **Every script sources `lib/common.sh`**, which applies `set -euo pipefail`
   and loads its own config.

---

## Install sequence

1. Boot the Arch ISO.
2. `pacman -Sy git`; clone this repository.
3. Place `host.conf`; confirm `drives.conf` matches
   `lsblk -d -o PATH,SIZE,ROTA,MODEL,SERIAL`.
4. `install/00-preflight.sh` — reports firmware mode and TRIM support,
   resolves every serial to a device, prints the exact device it will destroy,
   and waits for typed confirmation.
5. `install/01-partition.sh`, `02-pacstrap.sh`, `03-chroot.sh`. The repository
   is copied into the target at `/opt/stack` with `.git` intact. The user, SSH
   key and sshd are configured so the first boot is reachable without a
   keyboard.
6. Reboot, remove the USB, SSH back in.
7. `cd /opt/stack && sudo ./run.sh` — pauses once for you to authenticate the
   machine on the tailnet, then continues on its own.
8. `tools/verify.sh`
9. `sudo ./deploy.sh` — starts every app and makes it reachable.

Steps 7–9 assume two pieces of Tailscale state that belong to the tailnet
rather than to this machine, and so are applied once and never again: **HTTPS
Certificates** enabled under DNS, and the policy from
`apps/vaultwarden/tailnet-policy.hujson` under Access Controls.

---

## `run.sh`

```
./run.sh                 all bootstrap steps, in order
./run.sh --only 40,50    just these
```

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

Application state lives on ext4, not Btrfs: app state should not be rewound by
an OS snapshot rollback. p3 takes the full remainder.

**Pool**: mergerfs at `/mnt/pool` over `/mnt/disk1`–`/mnt/disk3`, with parity
at `/mnt/parity1` outside the pool. SnapRAID gives single-drive-failure
protection. All mounts are by label with `nofail` and a short device timeout,
so a dead drive degrades the pool instead of dropping the host to an emergency
shell. Branch mountpoints are locked (`chmod 0000`, `chattr +i`) before first
mount, so an unmounted drive cannot silently present an empty
root-filesystem directory as a writable pool branch.

**OS**: `Arch` using `linux-lts`. GRUB with `snapper` + `snap-pac` + 
`grub-btrfs`, so every package transaction is bracketed by bootable snapshots. 
zram swap, journald capped at 1 GiB, minimal package set, nothing that builds 
kernel modules.

**Access**: sshd keys-only with no root login and no password auth; Tailscale
with `--ssh` as an independent second path to a shell. Nothing forwarded at
the router.

**Reachability**: services bind `127.0.0.1` and are exposed by `tailscale
serve`, declared per app in `apps/<name>/serve.conf` and converged by
`deploy.sh` on every run — because that state lives in tailscaled and does not
survive a rebuild. Vaultwarden additionally sets `FUNNEL=yes`, the one
deliberate public exception, gated by a per-app guard script that runs
immediately before the port opens.

**Monitoring**: `smartd` on all five drives with persistent state files —
without them smartd re-baselines on every restart and will not report a change
that happened across a reboot. Push notifications via ntfy for unit failures,
SMART attribute movement, and SnapRAID sync/scrub results. An hourly heartbeat
and per-timer success pings to a hosted dead-man service, so a timer that
silently stops firing is caught by absence.
