# Ayakalea Toolkit

The Ayakalea Toolkit is the recommended deployment method for on-premises
installs of Ayakalea (and Overleaf Community Edition). It manages the whole
stack with `docker compose` and a small set of scripts that wrap `docker`.

Full documentation: <https://ayakaleaf-pro.ayaka.space>

This is a **hard fork** of the Overleaf toolkit (ayaka-notes/toolkit):
SaaS-era assumptions, the `SERVER_PRO` gating and the scattered image
settings are gone. The stack, services and configuration model the
on-premises system as it actually runs.

## The stack

| Service          | Image (config/images.env) | Surfaces to host |
|------------------|---------------------------|------------------|
| `ayakalea`       | app image (6.3.4)         | no (nginx proxies, or direct when proxy off) |
| `mongo`          | `mongo:9.0`               | no |
| `redis`          | `redis:8.10-alpine`       | no |
| `git-bridge`     | git-bridge (6.3.4)        | no |
| `nginx`          | `nginx:alpine3.24-slim`   | yes: 80/443 |
| `seaweedfs-master/volume/filer/s3` | `chrislusf/seaweedfs` | s3 only on `127.0.0.1:8333` |

All services live on the internal bridge network **`ayaka-network`**
(created automatically if missing). The app container is reachable inside
the network as `ayakalea`, and — for backward compatibility — also under the
aliases `overleaf` and `sharelatex`; the MongoDB database keeps the name
`sharelatex`.

## Layout

```
bin/            one script per task (thin wrappers over lib/toolkit-core.sh)
lib/
  toolkit-core.sh   all config loading, variable resolution, compose assembly
  compose/          one compose fragment per service
  config-seed/      seeds for config/ (overleaf.rc, images.env, variables.env, nginx.conf)
config/           YOUR configuration (created by bin/init, never touched without your say-so)
data/             persistent data (overleaf, mongo, redis, git-bridge, seaweedfs)
doc/              migration notes
```

## Configuration

| File                    | What it holds |
|-------------------------|---------------|
| `config/overleaf.rc`    | toolkit settings: services, paths, ports, TLS proxy |
| `config/images.env`     | **every container image name, in one place** |
| `config/variables.env`  | application environment (loaded into the app) |
| `config/nginx/`         | nginx config + certificates (when the TLS proxy is on) |
| `config/docker-compose.override.yml` | optional: per-instance compose overrides |

### Images in one place

`config/images.env` is the single resource file for all image names and
tags. To upgrade a service, change its line and run `bin/up`:

```env
AYAKALEA_IMAGE=ghcr.io/ayaka-notes/overleaf-pro:6.3.4
MONGO_IMAGE=mongo:9.0
REDIS_IMAGE=redis:8.10-alpine
GIT_BRIDGE_IMAGE=ghcr.io/ayaka-notes/overleaf-pro/git-bridge:6.3.4
NGINX_IMAGE=nginx:alpine3.24-slim
SEAWEEDFS_IMAGE=chrislusf/seaweedfs:latest
TEXLIVE_IMAGE=ghcr.io/ayaka-notes/texlive-full:2026.1
```

The toolkit derives `TEX_LIVE_DOCKER_IMAGE` / `ALL_TEX_LIVE_DOCKER_IMAGES`
/ `ALL_TEX_LIVE_DOCKER_IMAGE_NAMES` from `TEXLIVE_IMAGE`, so TeX Live
versions are also set in exactly one line.

## Quick start

```sh
git clone <this repo> ayakalea-toolkit && cd ayakalea-toolkit
bin/init                 # create config/ and generate secrets
# edit config/overleaf.rc, config/images.env, config/variables.env
bin/up -d                # pull TeX Live image, start the stack
bin/doctor               # check the deployment
```

For a TLS-terminated instance: `bin/init --tls`, then put a real
certificate into `config/nginx/certs/` (or point `TLS_*_PATH` at yours),
set `NGINX_ENABLED=true` and `bin/up`.

## Commands

| Command | Purpose |
|---|---|
| `bin/init [--tls]` | create `config/` (never overwrites); `--tls` adds nginx config + example cert |
| `bin/up [flags]` | create/recreate containers (runs after config edits); pulls TeX Live images |
| `bin/start` / `bin/stop` | start/stop existing containers (no config applied) |
| `bin/docker-compose` | transparent `docker compose` wrapper (ps, logs, exec, down, …) |
| `bin/doctor` | installation + runtime health report (exits non-zero on errors) |
| `bin/logs [-f] [-n N] [svc…]` | app microservice and container logs |
| `bin/error-logs [-f] [svc…]` | error lines only |
| `bin/shell` | shell inside the app container |
| `bin/mongo` | mongo shell, already in the app database |
| `bin/run-script [ls]` | run server scripts inside the app |
| `bin/images` | show every configured image + local status |
| `bin/pull-texlive` | pull TeX Live images (+ prints a cron line for auto-updates) |
| `bin/backup-config [-m zip\|tar\|copy] DEST` | back up `config/` |
| `bin/upgrade` | guided upgrade: toolkit, app image (images.env), backup, restart |
 `bin/rename-env-vars-5-0`, `bin/rename-rc-vars` | migrate old `SHARELATEX_*` variable names |
| `bin/migrate-s3 preflight|wipe|import|verify|all` | filesystem → S3 filestore migration (see below) |

## Merging an existing Overleaf instance (filesystem → S3)

Move a legacy local-filestore Overleaf (e.g. a compose_cep backup) into the
toolkit's S3 filestore without re-creating projects:

```sh
export LEGACY_ROOT=/path/to/legacy-backup   # dir that was bind-mounted as /var/lib/overleaf
bin/migrate-s3 preflight                    # read-only readiness check + config diff vs legacy .env
bin/migrate-s3 wipe --yes                   # optional: blank-slate the four S3 buckets
bin/migrate-s3 import --reimport [--with-exports]   # upload + MD5 verification
bin/migrate-s3 verify                       # automated checks + manual UI checklist
bin/migrate-s3 all --yes-all --wipe         # full runbook with human gates
```

The tool moves `user_files/`, `template_files/`, `history/overleaf-chunks/`,
`history/overleaf-project-blobs/` (and optional `output/`, `*.zip` exports)
using the official Overleaf key rules; the legacy data is never modified. The
S3 endpoint, buckets and credentials are resolved from the toolkit config
automatically. Requires `python3` + `boto3` on the host (`pip install boto3`).

Notes:
- SeaweedFS 4.50 needs ~30 GB of free disk per new volume — plan the
  SeaweedFS data disk accordingly.
- After migrating, keep `OVERLEAF_INVITE_TOKEN_SECRET` and the OIDC
  client-credentials identical to the legacy server (preflight diffs them).

## What changed vs the upstream toolkit (hard fork)

* **SaaS removed** — no `SERVER_PRO` flag, no overleaf.com/Server-Pro
  gating, no overleaf.com links. Sandboxed compiles, git-bridge, external
  auth, S3 and the TLS proxy are first-class, not "Pro only".
* **Images in one file** — `config/images.env` replaces the
  `config/version` + scattered `*_IMAGE`/`*_VERSION` variables. A legacy
  `config/version` still works (folded into `images.env`, with a warning).
* **One shared core** — `lib/toolkit-core.sh` replaces `lib/shared-functions.sh`
  plus ~30 duplicated bootstrap lines per script.
* **ayaka-network** — every service lives on a shared internal network;
  only nginx (and the loopback S3 API) publish host ports. The app is no
  longer published on the host when the proxy is enabled.
* **ayakalea naming with backward compatibility** — app container/hostname
  is `ayakalea`, with network aliases `overleaf` + `sharelatex`; the Mongo
  database stays `sharelatex`.
* **SeaweedFS** — filestore + history S3 storage is a managed part of the
  stack (four services, buckets, generated S3 keys).
* **Dropped** — Podman/SELinux setup, docker-compose v1 era code, the
  20 scattered doc pages (now on the docs site), `bin/podman-setup`.

See `doc/migration-from-overleaf-toolkit.md` for the migration steps.
