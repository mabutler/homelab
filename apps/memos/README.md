# Memos

Quick notes — the thing you open to write one line down. Single container,
SQLite, tailnet only, no configuration.

Reachable at `https://fidelacchius.<tailnet>.ts.net:8447`.

## First run

```bash
cd /opt/stack && sudo ./deploy.sh memos
```

No environment file: everything is set in the UI after first start. **The first
account created becomes the host account**, so open it and register
immediately — same window as Immich, closed by the act of registering.

Then in **Settings → Workspace → General**, turn off public sign-up.

## State

`/opt/appdata/memos` — SQLite database and any uploaded attachments.

## Backup

Captured nightly by `homelab-backup`: the database via SQLite `.backup`, then
the whole directory (attachments live here too, and the live database file
itself is excluded from the snapshot — only the dump represents it). See
[`docs/backup-inventory.md`](../../docs/backup-inventory.md) for the exact
mechanism.

Restored automatically by `bootstrap/85-restore.sh` on a fresh install — the
directory and the database both come back, no manual step needed. It only
acts when `/opt/appdata/memos` does not already exist, so a live host is
never touched. There is no `memos.env` to restore — this app has none.

## Why RunInit

`RunInit=true` (podman's `--init`) is in the unit because upstream's own
`docker run` uses it: memos does not reap its own child processes, and without
a PID 1 that does, zombies accumulate across a long uptime. On a machine meant
to run for months between reboots that matters more than it would elsewhere.

## Updates

`stable` with `AutoUpdate=registry`. Memos moves quickly on `latest`; `stable`
is the tag upstream intends for people who are not watching.
