# Homepage

The dashboard. One page with everything on it, on the tailnet at
`https://fidelacchius.<tailnet>.ts.net:8448`.

Two containers: Homepage itself, and a **read-only proxy in front of the Podman
socket**.

---

## Why the proxy exists

Homepage draws a running/stopped dot next to each service. To do that it needs
to ask Podman what is running — and **access to the Podman socket is root on
this host.** That API can create a container, bind-mount `/` into it, and run
anything as root.

Mounting the socket `:ro` does not help, and this is the trap worth
understanding: read-only applies to the socket **file**, not to the API. Every
dangerous verb is a POST, and a read-only mount does nothing to stop a POST.

So Homepage never sees the socket. `homepage-socket-proxy` is an HAProxy
whitelist with `CONTAINERS=1` and everything else `0` — it answers the
container-listing endpoints and returns 403 for the rest, including every
write. It is not published to the host at all; it exists only on the `homepage`
network, so Homepage is the only thing that can reach it.

---

## The config is in git

`apps/homepage/config/` is bind-mounted to `/app/config`. The dashboard's
contents are configuration, not state, so they are version controlled and
edited in the repository:

```bash
vim apps/homepage/config/services.yaml
git commit && git push          # then pull on the server
sudo systemctl restart homepage
```

A rebuilt host comes back with its services already on the page.

| File | What |
|---|---|
| `services.yaml` | the tiles, their links and which container each watches |
| `settings.yaml` | title, layout, group order |
| `widgets.yaml` | CPU, memory and the three disks worth watching |
| `bookmarks.yaml` | admin consoles you always have to go looking for |
| `docker.yaml` | points at the proxy — **never** at a socket |

The mount is read-write, not read-only: Homepage creates any config file it
finds missing, and refusing it that turns an absent file into a crash. All of
them are shipped, so it does not write in practice.

---

## First run

```bash
cd /opt/stack
sudo cp apps/homepage/homepage.env.example apps/homepage/homepage.env
sudo vim apps/homepage/homepage.env      # HOMEPAGE_ALLOWED_HOSTS
sudo ./deploy.sh homepage
```

**`HOMEPAGE_ALLOWED_HOSTS` is mandatory and includes the port.** Homepage
refuses any request whose `Host` header is not listed, and the refusal is a
bare "host not allowed" page — which reads like the app is broken rather than
like a setting is wrong. If the dashboard loads blank or errors, check this
first.

---

## Adding a service

Append to `services.yaml`. `href` is the **tailnet** URL with its port — these
links are followed by your browser, which has no `127.0.0.1:8222`. `container:`
must match the `ContainerName=` in that app's unit, or the status dot stays
grey.

The port each app is on is in the RUNBOOK's application table.

---

## What this does not do

No metrics history, no alerting, no control — it cannot start or stop anything,
by design. It is a map of the house and a set of links. The alerting that
matters is ntfy and Healthchecks, and neither depends on this being up.
