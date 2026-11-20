# Migrating from the Overleaf toolkit to the Ayakalea Toolkit

The Ayakalea Toolkit is a hard fork of the Overleaf toolkit
(ayaka-notes/toolkit). Your data, config and image names carry over; the
file layout and a few variable names change.

## What stays the same

* `config/` layout: `overleaf.rc`, `variables.env`, `nginx/`,
  `docker-compose.override.yml`
* `data/` layout: `data/overleaf`, `data/mongo`, `data/redis`,
  `data/git-bridge`
* bin command names: `init`, `up`, `start`, `stop`, `logs`, `error-logs`,
  `shell`, `mongo`, `docker-compose`, `doctor`, `backup-config`,
  `run-script`, `upgrade`, `rename-env-vars-5-0`, `rename-rc-vars`
* app environment variables (`variables.env`) — unchanged
* app data compatibility: Mongo DB `sharelatex`, replSet `overleaf`,
  container reachable as `ayakalea`, `overleaf`, `sharelatex`

## What changes

| Old toolkit | Ayakalea Toolkit |
|---|---|
| image name + `config/version` | `config/images.env` (one file for all images) |
| `OVERLEAF_IMAGE_NAME` in `overleaf.rc` | `AYAKALEA_IMAGE` in `images.env` |
| `MONGO_IMAGE` + `MONGO_VERSION` | `MONGO_IMAGE` in `images.env` (full `repo:tag`) |
| `REDIS_IMAGE` (rc) | `REDIS_IMAGE` in `images.env` |
| `GIT_BRIDGE_IMAGE` (rc) | `GIT_BRIDGE_IMAGE` in `images.env` |
| `NGINX_IMAGE` (rc) | `NGINX_IMAGE` in `images.env` |
| `TEX_LIVE_DOCKER_IMAGE` / `ALL_TEX_LIVE_DOCKER_IMAGES` in `variables.env` | `TEXLIVE_IMAGE` in `images.env` (derived) |
| `SERVER_PRO=true` + `SIBLING_CONTAINERS_ENABLED=true` | `SIBLING_CONTAINERS_ENABLED=true` (no Pro flag) |
| `sharelatex` container name | `ayakalea` (aliases `overleaf`, `sharelatex`) |
| app port published on the host always | app published only without the TLS proxy |
| `bin/podman-setup` | removed (Docker only) |

## Steps

1. Back up: `bin/backup-config -m tar /path/to/config-backup.tar` and
   back up `data/` (see the docs site, "Data and backups").
2. Stop the old instance: `bin/stop`.
3. Replace the toolkit checkout with the Ayakalea Toolkit. Keep `config/`
   and `data/` in place.
4. Create `config/images.env` (or run `bin/init` in a fresh directory and
   copy your `overleaf.rc`/`variables.env`/`nginx/` into it). Copy the
   image references out of the old `overleaf.rc`/`version` into it.
5. Remove (or keep as overrides) from `overleaf.rc`:
   `SERVER_PRO`, `OVERLEAF_IMAGE_NAME`, `MONGO_VERSION`,
   `GIT_BRIDGE_IMAGE` — image names now live in `images.env`.
   `bin/doctor` warns while `config/version` still exists.
6. `bin/up -d`, then `bin/doctor`.
7. Optional: `bin/rename-env-vars-5-0` / `bin/rename-rc-vars` for any
   leftover `SHARELATEX_*` names.

## Rollback

Old toolkit + your kept `config/` + `data/`. Nothing in `data/` changes
format. The app image is the only hard dependency: the old `config/version`
value still works with the old toolkit.
