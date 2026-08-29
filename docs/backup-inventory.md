# Backup inventory

**What has to be backed up, and how each thing has to be captured.** Written as
applications are deployed rather than at Phase 4, because the "how" is
per-application knowledge that is easy to have and hard to reconstruct.

Nothing here is implemented yet — Phase 4 (restic to Backblaze B2) is what
implements it. This is the specification that phase has to satisfy.

> **The rule that generates most of this file:** a running database cannot be
> backed up by copying its files. You get a torn image that restores as
> corruption, and you find out on the day you need it. Every database below has
> a documented way to produce a consistent copy; use it, in a pre-hook.

---

## Tier 1 — irreplaceable

Losing these means losing something that cannot be recreated from anywhere.

### Vaultwarden

| | |
|---|---|
| Path | `/opt/appdata/vaultwarden` |
| Contains | `db.sqlite3`, attachments, **RSA keys**, `config.json`, icon cache |
| Capture | `sqlite3 db.sqlite3 ".backup '/tmp/vw.sqlite3'"` as a **pre-hook**, then back up the snapshot |
| Frequency | Daily |

**Never copy `db.sqlite3` from a running server.** A live-copied SQLite file
restores as a corrupt database.

The RSA keys in that directory are not regenerable — without them the encrypted
vault data is unreadable even with a good database. Back up the *whole*
directory, not just the database.

**The circular dependency:** `vaultwarden.env` holds `DOMAIN` and
`ADMIN_TOKEN`, and the restore procedure needs it. It cannot live only in
Vaultwarden. Keep a copy somewhere reachable when the vault is down — printed,
or in a second password manager.

### Immich — database

| | |
|---|---|
| Path | `/opt/appdata/immich/postgres` |
| Capture | `pg_dump` from the running container. **Not** a file copy of the data directory. |
| Frequency | Daily |

```bash
podman exec immich-database pg_dump -U postgres --clean --if-exists immich \
  | gzip > /opt/appdata/immich/dump/immich.sql.gz
```

Immich's own docs are specific that a plain `pg_dumpall` is not sufficient for
some versions because of the vector extensions — **check the current Immich
backup documentation when Phase 4 is written**, not this file, since it changes
with their schema.

### Immich — the photos

| | |
|---|---|
| Path | `/mnt/pool/photos` |
| Capture | Plain file copy. |
| Frequency | Daily |

**The database and the photos are two halves of one thing.** The database holds
albums, faces, metadata and the paths; the files are the content. A restore
that mixes a database from Tuesday with files from Thursday gives a library
that does not match itself. Back them up in the same run, and restore them as a
pair.

This is the largest thing on the machine and the main driver of B2 cost.

### Host identity

| | |
|---|---|
| Paths | `host.conf`, `apps/*/*.env`, `/etc/homelab/alerting.env` |
| Capture | Plain file copy. |
| Frequency | On change |

All gitignored, all unrecoverable from the repository. The repo restores the
*machine*; these restore *this* machine. `alerting.env` holds the ntfy topic,
which is a credential — anyone who has it can read every alert and publish
convincing fakes.

---

## Tier 2 — painful but recreatable

- **SnapRAID content files** (`/mnt/disk*/snapraid.content`). Regenerable by a
  full sync, which is slow. Worth including; not worth panicking over.
- **`/mnt/pool`, other than photos.** Whatever lands here later. SnapRAID
  protects it against *drive failure*, which is not the same as a backup: it
  does not protect against deletion, corruption, fire or theft.

## Not backed up, deliberately

- `/var/lib/containers` — images, all re-pullable.
- `/opt/appdata/immich/model-cache` — re-downloaded on demand.
- Valkey — a job queue. Losing it costs a re-scan.
- The OS. It is `install/` plus `bootstrap/` plus `host.conf`, and a rebuild is
  the tested path. Snapshots cover the day-to-day mistakes.

---

## Restore drills

A backup nobody has restored is a hypothesis. Phase 5 should include, at least
once:

1. Restore Vaultwarden to a scratch directory, point a container at it, log in.
2. Restore the Immich database and a subset of photos, confirm the library
   matches itself.
3. Confirm the restore works with only what is in B2 plus the git repo — no
   file that happens to still be on the machine.
