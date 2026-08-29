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

## Why RunInit

`RunInit=true` (podman's `--init`) is in the unit because upstream's own
`docker run` uses it: memos does not reap its own child processes, and without
a PID 1 that does, zombies accumulate across a long uptime. On a machine meant
to run for months between reboots that matters more than it would elsewhere.

## Updates

`stable` with `AutoUpdate=registry`. Memos moves quickly on `latest`; `stable`
is the tag upstream intends for people who are not watching.
