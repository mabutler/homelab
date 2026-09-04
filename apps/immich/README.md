# Immich

Photo and video server. Three containers as deployed — the server, PostgreSQL
and a Valkey job queue — plus machine learning, which is written but parked in
[`optional/`](optional/README.md).

**Tailnet only, permanently.** Unlike Vaultwarden there is no version of this
that goes on the public internet — it is every photo you have, sitting in plain
files that a server compromise hands over whole. `serve.conf` parks it on port
8444, outside the three ports Tailscale will Funnel, so it cannot be published
by mistake.

---

## Before you start: this hardware

Immich's machine learning does CLIP embeddings and face detection. On a 2011
Sandy Bridge i3 with no AVX2, **an initial library scan takes days, not hours**,
and pins the CPU while it runs.

That is background work and Immich stays usable throughout — uploads, browsing
and albums do not wait for it. But it is the difference between "quiet server"
and "the machine sounds busy for a week", and it is worth knowing before you
point it at twenty years of photos.

The ML container is capped (`CPUWeight=20`, `MemoryMax=3G`) so it cannot starve
Vaultwarden or the pool. Raise it if you would rather the scan finished sooner.

**It is not deployed.** The unit lives in
[`optional/`](optional/README.md), which `deploy.sh` does not glob. Search by
filename, date and album work; search by content ("beach", "dog") and face
grouping do not. Turn it on whenever you like — Immich backfills, so nothing is
lost by waiting until you know how the rest behaves on this hardware.

---

## Layout

| What | Where | Why |
|---|---|---|
| Photos and video | `/mnt/pool/photos` | Bulk data. This is what the pool is for. Created by an `ExecStartPre` in the unit, which refuses if the pool is not mounted — podman will not create a bind-mount source, and tmpfiles.d would make it on the SSD before the pool is up. |
| PostgreSQL | `/opt/appdata/immich/postgres` | ext4. Databases behave badly on Btrfs CoW, and app state must not be rewound by an OS snapshot rollback. **Owned by Postgres, not by us** — created by `mkdir` in the unit and deliberately absent from `system/tmpfiles/`, which would re-assert root ownership on every boot. |
| ML model cache | `/opt/appdata/immich/model-cache` | Created but unused until ML is deployed; a few hundred MB re-downloaded on every restart otherwise. |

The database and the photos are **two halves of one thing** — the database
holds the metadata, albums, faces and the paths. Restoring one without the
other gives you a library that does not match itself — see [Backup](#backup).

---

## First run

### 1. The secrets file

```bash
cd /opt/stack
sudo cp apps/immich/immich.env.example apps/immich/immich.env
sudo vim apps/immich/immich.env
```

Set `DB_PASSWORD` and `POSTGRES_PASSWORD` to the **same** value —
`openssl rand -hex 24`, letters and digits only. Immich's own docs warn that
punctuation in the password breaks the connection URI.

`POSTGRES_*` is read **only on first start**, when the database initialises
itself. Changing it afterwards does not change the database; it just stops the
server logging in.

**Put a copy in Vaultwarden.** The database is worthless without it.

### 2. Deploy

```bash
sudo ./deploy.sh immich
```

This starts all three services and then serves it on the tailnet. First start
pulls roughly 2 GB of images and runs migrations against an empty database; on
this hardware, give it time.

```bash
journalctl -u immich -f
systemctl status immich immich-database immich-redis
```

### 3. Open it

`https://fidelacchius.<tailnet>.ts.net:8444` from any tailnet device.

The **first account registered becomes the admin.** Register yours immediately,
before anyone else reaches it — this is the same open-registration window
Vaultwarden had, and here it is closed by the act of registering rather than by
a setting.

Then add your partner from **Administration → Users**, rather than letting them
self-register.

### 4. The mobile apps

Install Immich from the app store, choose **Custom server**, and give it the
same URL including `:8444`. Enable background backup so phones upload on their
own — that is the point of the exercise.

Phones must be on the tailnet for this to work, including when they are on
cellular. That is the trade for not publishing it.

---

## Operating

```bash
systemctl status immich
journalctl -u immich -n 100
systemctl restart immich          # pulls the others up with it
```

`immich.service` `Requires=` the database and Valkey, so starting it starts
them. Stopping it does **not** stop them — stop those explicitly if you mean to.

### Updates

`AutoUpdate=registry` everywhere, applied by the daily `podman-auto-update`
timer — **including the database, because its tag is the pin**:

```
ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0
```

That names the PostgreSQL major and both extension versions, so auto-update can
only deliver a rebuild of that same combination: a patched 14.x with the same
extensions, needing no migration. Pinning is what makes leaving auto-update on
safe, not a contradiction of it.

**Do you have to track Immich's recommendation? Yes — but by hand.** Their
database image is not just "Postgres", and when they move it the move usually
carries a step no image swap performs:

- A **PostgreSQL major** bump changes the on-disk format. The new binary
  refuses to start on the old data directory — it fails closed rather than
  corrupting anything, but you are down until `pg_upgrade` or a dump/restore.
  Postgres does not downgrade.
- A **VectorChord** bump needs SQL afterwards:
  ```sql
  ALTER EXTENSION vchord UPDATE;
  REINDEX INDEX face_index;
  REINDEX INDEX clip_index;
  ```
  Skip it and the database starts, serves, and quietly has stale indexes.

Neither can be done by `podman-auto-update` at 05:00 unattended, which is the
whole reason the version lives in the tag.

Immich supports PostgreSQL **14 through 19**, so a pinned 14 will not be outrun
by server updates for years — the two are not on a collision course.

And because a pin nobody watches is just a stale version:

```bash
sudo ./tools/check-image-pins.sh
```

compares this tag against Immich's current release and tells you when they have
diverged, with the migration steps. It is in the quarterly ritual.

Immich itself moves fast. The server and (if deployed) ML images must be on the
**same release**; they pull independently, so a partial update leaves them
mismatched, which presents as ML jobs failing rather than as anything obviously
version-related.

```bash
sudo podman inspect immich-server --format '{{.ImageName}}'
```

---

## Backup

`/opt/appdata/immich/postgres` is captured with `pg_dump` from the running
container, nightly, never as a file copy — and **together with**
`/mnt/pool/photos`, since the database and the files are two halves of one
library. See [`docs/backup-inventory.md`](../../docs/backup-inventory.md) for
the exact mechanism.

**Restoring is not fully automatic, and this is the one app where that
matters.** `bootstrap/85-restore.sh` brings the photos and `immich.env` back
on its own on a fresh install. The database does not: `pg_restore` needs a
running container, which does not exist yet at that point in the sequence, so
the dump is staged and the script prints the command to finish it —

```bash
sudo ./deploy.sh immich
gunzip -c /var/lib/homelab/restore/immich.sql.dump.gz | \
  sudo podman exec -i -e PGPASSWORD=$(grep -m1 '^DB_PASSWORD=' \
    apps/immich/immich.env | cut -d= -f2-) immich-database \
  psql -U postgres immich
```

run it before trusting the library. Photos with no matching database is a
rebuild that looks done and is not.
