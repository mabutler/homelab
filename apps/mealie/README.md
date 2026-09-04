# Mealie

Recipe manager and meal planner. Single container, SQLite, tailnet only.

Reachable at `https://fidelacchius.<tailnet>.ts.net:8445`.

## First run

```bash
cd /opt/stack
sudo cp apps/mealie/mealie.env.example apps/mealie/mealie.env
sudo vim apps/mealie/mealie.env       # BASE_URL must be the real address
sudo ./deploy.sh mealie
```

`BASE_URL` has to be the URL you actually type, port included. Mealie builds
links against it — get it wrong and the app loads but shares, images and the
API calls point somewhere that does not exist.

Default login on a fresh install is **changeme@example.com / MyPassword**.
Change it immediately; `ALLOW_SIGNUP=false` means that account is the only way
in until you create others from the admin panel.

## State

`/opt/appdata/mealie` — SQLite database plus uploaded recipe images.

## Backup

Captured nightly by `homelab-backup`: the database via SQLite `.backup`, then
the whole directory (recipe images live here too, and the live database file
itself is excluded from the snapshot — only the dump represents it). See
[`docs/backup-inventory.md`](../../docs/backup-inventory.md) for the exact
mechanism.

Restored automatically by `bootstrap/85-restore.sh` on a fresh install — the
directory and the database both come back, no manual step needed. It only
acts when `/opt/appdata/mealie` does not already exist, so a live host is
never touched.

## Updates

Pinned to `v3.24.0` rather than `latest`. Mealie has shipped schema migrations
in point releases, and a database migrated forward overnight against an image
that then rolls back is not a situation to be in unattended. `AutoUpdate` will
only pick up rebuilds of that tag; moving it is a deliberate act.

## The bit worth knowing

Recipe *import from a URL* is the feature you will actually use, and it makes
outbound requests from the server. That works today, but note the tailnet
policy denies `tag:server` outbound access to the tailnet — not to the public
internet, which is what this needs. If imports ever start failing, check
whether that policy has been tightened.
