# Vikunja

Tasks and lists. Single container, SQLite, tailnet only.

Reachable at `https://fidelacchius.<tailnet>.ts.net:8446`.

## First run

```bash
cd /opt/stack
sudo cp apps/vikunja/vikunja.env.example apps/vikunja/vikunja.env
sudo vim apps/vikunja/vikunja.env
sudo ./deploy.sh vikunja
```

Two values matter and both bite quietly:

**`VIKUNJA_SERVICE_SECRET`** signs session tokens. `openssl rand -hex 32`.
Changing it logs everyone out; losing it means nobody can log in until it is
replaced and everyone signs in again. **Put it in Vaultwarden.**

**`VIKUNJA_SERVICE_PUBLICURL`** must be the address you actually type,
including the port and a **trailing slash**. The browser makes its API calls
against this value, so a wrong one gives you a page that loads and then fails
every request — which looks like a broken server rather than a config typo.

Register your account, then set `VIKUNJA_SERVICE_ENABLEREGISTRATION=false` and
redeploy. `deploy.sh` restarts the container when the env file changes.

## State

`/opt/appdata/vikunja/db` (SQLite) and `/opt/appdata/vikunja/files`
(attachments), kept separate so the backup rule is obvious: **both, together.**
A database referencing attachments that were not restored is worse than
neither.

## Backup

Captured nightly by `homelab-backup`: the database via SQLite `.backup`, then
the whole directory — `db/` and `files/` together, in the same run, for the
"both, together" reason above. The live database file itself is excluded from
the snapshot; only the dump represents it. See
[`docs/backup-inventory.md`](../../docs/backup-inventory.md) for the exact
mechanism.

Restored automatically by `bootstrap/85-restore.sh` on a fresh install — the
directory and the database both come back, no manual step needed. It only
acts when `/opt/appdata/vikunja` does not already exist, so a live host is
never touched.

## The uid

**Vikunja runs as uid 1000 inside the container and does not support
`PUID`/`PGID`.** Its data directories are therefore owned `1000:1000` in
`system/tmpfiles/apps-3c.conf`. Root-owned directories give a container that
starts, logs `config file not found, using defaults` — which is normal and not
the problem — and then fails on the first write. If you ever move or recreate
these paths by hand, chown them.

## Updates

`latest` with `AutoUpdate=registry`. This is a single container over SQLite
with two users — the blast radius of a bad update is a restart, and the
snapshot before it is a rollback.

Note the image is the **unified** one: since 0.24 the API and frontend are a
single container. Older guides describing a two-container split do not apply.
