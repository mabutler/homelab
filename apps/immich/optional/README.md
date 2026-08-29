# Optional units

`deploy.sh` globs `apps/<name>/*.container`, so nothing in this directory is
deployed. Moving a unit here is how you take a component out of an app without
deleting it or losing its comments and history.

## immich-machine-learning.container

CLIP embeddings (search by content — "beach", "dog") and face detection and
grouping. Everything else in Immich works without it: upload, browse, albums,
sharing, mobile backup, search by filename or date.

Not deployed initially because on a 2011 Sandy Bridge i3 with no AVX2 the
initial scan of a real photo library runs for **days** at 100% CPU. That is a
poor first impression of a new server and it is entirely optional work.

### Turning it on later

```bash
mv apps/immich/optional/immich-machine-learning.container apps/immich/
sudo ./deploy.sh immich
```

Then in **Administration → Settings → Machine Learning**, re-enable it. Immich
backfills — every photo already in the library gets processed, so nothing is
lost by having waited.

Watch the first day: `podman stats immich-machine-learning`. The unit caps
itself at `MemoryMax=3G` and `CPUWeight=20` so it cannot starve Vaultwarden.
