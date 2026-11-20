# shellcheck shell=bash
# =====================================================================
#  Ayakalea Toolkit — shared core (sourced by every bin/ script)
#
#  Provides:
#    ayakalea_prepare        load config, resolve variables, build the
#                            docker-compose flags (call once)
#    ayakalea_compose ARGS   run `docker compose` with the toolkit flags
#    ayakalea_require_config error out if config/ is not initialised
#    warning MSG             print a warning (suppressed with SKIP_WARNINGS)
#    note MSG                print an informational message
#    ayakalea_die MSG        print an error and exit 1
#
#  Config files (all in config/):
#    overleaf.rc     toolkit settings (services, paths, ports)
#    images.env      every container image name, in one place
#    variables.env   application environment (loaded into the app)
#    version         legacy: app image tag (migrated into images.env)
#    nginx/          nginx TLS proxy config + certificates
# =====================================================================

#### Detect Toolkit Project Root (core lives in <root>/lib/) ####
command -v realpath >/dev/null 2>&1 || realpath() {
  [[ $1 == /* ]] && echo "$1" || echo "$PWD/${1#./}"
}
AYAKALEA_TOOLKIT_ROOT="$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")"

function ayakalea_die() {
  echo "ERROR: $*" >&2
  exit 1
}

function warning() {
  [[ "${SKIP_WARNINGS:-false}" == "true" ]] && return 0
  echo "WARNING: $*" >&2
}

function note() {
  [[ "${SKIP_WARNINGS:-false}" == "true" ]] && return 0
  echo "AYAKALEA: $*" >&2
}

function has_docker() {
  command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1
}

function ayakalea_require_config() {
  for f in overleaf.rc variables.env images.env; do
    if [[ ! -f "$AYAKALEA_TOOLKIT_ROOT/config/$f" ]]; then
      ayakalea_die "config/$f not found. Run bin/init first."
    fi
  done
}

function apply_defaults() {
  # --- Identity ---
  : "${PROJECT_NAME:=ayakalea}"

  # --- App container ---
  : "${OVERLEAF_DATA_PATH:=data/overleaf}"
  : "${OVERLEAF_LISTEN_IP:=127.0.0.1}"
  : "${OVERLEAF_PORT:=80}"
  : "${OVERLEAF_LOG_PATH:=}"

  # --- Sandboxed compiles ---
  : "${SIBLING_CONTAINERS_ENABLED:=false}"
  : "${DOCKER_SOCKET_PATH:=/var/run/docker.sock}"
  : "${SIBLING_CONTAINERS_PULL:=true}"
  : "${PULL_BEFORE_UPGRADE:=true}"

  # --- Mongo ---
  : "${MONGO_ENABLED:=true}"
  : "${MONGO_DATA_PATH:=data/mongo}"
  : "${MONGO_REPLSET:=overleaf}"
  : "${MONGO_DB:=sharelatex}"

  # --- Redis ---
  : "${REDIS_ENABLED:=true}"
  : "${REDIS_DATA_PATH:=data/redis}"
  : "${REDIS_AOF_PERSISTENCE:=true}"

  # --- Git bridge ---
  : "${GIT_BRIDGE_ENABLED:=false}"
  : "${GIT_BRIDGE_DATA_PATH:=data/git-bridge}"
  : "${GIT_BRIDGE_LOG_LEVEL:=INFO}"

  # --- SeaweedFS S3 storage ---
  : "${SEAWEEDFS_ENABLED:=false}"
  : "${SEAWEEDFS_DATA_PATH:=data/seaweedfs}"
  : "${SEAWEEDFS_S3_HOST:=127.0.0.1}"
  : "${SEAWEEDFS_S3_PORT:=8333}"

  # --- nginx TLS proxy ---
  : "${NGINX_ENABLED:=false}"
  : "${NGINX_CONFIG_PATH:=config/nginx/nginx.conf}"
  : "${NGINX_HTTP_PORT:=80}"
  : "${NGINX_HTTP_LISTEN_IP:=127.0.1.1}"
  : "${NGINX_TLS_LISTEN_IP:=127.0.1.1}"
  : "${TLS_PORT:=443}"
  : "${TLS_PRIVATE_KEY_PATH:=config/nginx/certs/ayakalea_key.pem}"
  : "${TLS_CERTIFICATE_PATH:=config/nginx/certs/ayakalea_certificate.pem}"

  # --- Images (defaults only; config/images.env normally sets these) ---
  : "${AYAKALEA_IMAGE:=ghcr.io/ayaka-notes/overleaf-pro:6.3.4}"
  : "${MONGO_IMAGE:=mongo:9.0}"
  : "${REDIS_IMAGE:=redis:8.10-alpine}"
  : "${GIT_BRIDGE_IMAGE:=ghcr.io/ayaka-notes/overleaf-pro/git-bridge:6.3.4}"
  : "${NGINX_IMAGE:=nginx:alpine3.24-slim}"
  : "${SEAWEEDFS_IMAGE:=chrislusf/seaweedfs:latest}"
  : "${TEXLIVE_IMAGE:=ghcr.io/ayaka-notes/texlive-full:2026.1}"
}

function source_config_files() {
  # overleaf.rc first, then images.env (the single source for images),
  # then variables.env (application environment).
  local f
  for f in overleaf.rc images.env variables.env; do
    local file="$AYAKALEA_TOOLKIT_ROOT/config/$f"
    if [[ -f "$file" ]]; then
      set -a
      # shellcheck disable=SC1090
      . "$file"
      set +a
    fi
  done
}

function migrate_legacy_image_settings() {
  # Old Overleaf toolkit style: image name in overleaf.rc + tag in config/version.
  # Keep working, but the new home for every image name is config/images.env.
  local version_file="$AYAKALEA_TOOLKIT_ROOT/config/version"
  if [[ -f "$version_file" ]]; then
    local v
    v="$(head -n 1 "$version_file" | tr -d '[:space:]')"
    if [[ -n "${OVERLEAF_IMAGE_NAME:-}" && -z "${AYAKALEA_IMAGE:-}" ]]; then
      AYAKALEA_IMAGE="${OVERLEAF_IMAGE_NAME}:${v}"
    fi
    local cur
    cur="${MONGO_IMAGE:-}"
    if [[ -n "$cur" && "$cur" != *:* ]]; then MONGO_IMAGE="${cur}:${v}"; fi
    cur="${GIT_BRIDGE_IMAGE:-}"
    if [[ -n "$cur" && "$cur" != *:* ]]; then GIT_BRIDGE_IMAGE="${cur}:${v}"; fi
    warning "config/version is legacy: its value is folded into config/images.env. Remove it after checking bin/images."
  fi
}

function canonicalize_path() {
  # $1 = variable name; make relative paths absolute against the toolkit root
  # (no namerefs: must work on the bash 3.2 shipped with macOS)
  eval "val=\${$1:-}"
  if [[ -n "$val" && "$val" != /* ]]; then
    val="$AYAKALEA_TOOLKIT_ROOT/$val"
  fi
  eval "$1=\"$val\""
}

function resolve_derived_vars() {
  # --- paths ---
  canonicalize_path OVERLEAF_DATA_PATH
  canonicalize_path MONGO_DATA_PATH
  canonicalize_path REDIS_DATA_PATH
  canonicalize_path GIT_BRIDGE_DATA_PATH
  canonicalize_path SEAWEEDFS_DATA_PATH
  [[ -n "$OVERLEAF_LOG_PATH" ]] && canonicalize_path OVERLEAF_LOG_PATH
  [[ -n "$NGINX_CONFIG_PATH" ]] && canonicalize_path NGINX_CONFIG_PATH
  [[ -n "$TLS_PRIVATE_KEY_PATH" ]] && canonicalize_path TLS_PRIVATE_KEY_PATH
  [[ -n "$TLS_CERTIFICATE_PATH" ]] && canonicalize_path TLS_CERTIFICATE_PATH

  # --- mongo ---
  if [[ "$MONGO_ENABLED" == "true" ]]; then
    MONGO_URL="mongodb://mongo/${MONGO_DB}"
  elif [[ -z "${MONGO_URL:-}" ]]; then
    ayakalea_die "MONGO_ENABLED=false requires MONGO_URL in config/overleaf.rc"
  fi
  OVERLEAF_MONGO_URL="$MONGO_URL"

  # --- redis ---
  if [[ "$REDIS_ENABLED" == "true" ]]; then
    REDIS_HOST="redis"
    REDIS_PORT="6379"
  fi
  OVERLEAF_REDIS_HOST="${OVERLEAF_REDIS_HOST:-${REDIS_HOST:-redis}}"
  REDIS_COMMAND="redis-server --save 60 1 --loglevel warning"
  [[ "$REDIS_AOF_PERSISTENCE" == "true" ]] && REDIS_COMMAND="$REDIS_COMMAND --appendonly yes"

  # --- tex live images (single source: images.env TEXLIVE_IMAGE) ---
  TEX_LIVE_DOCKER_IMAGE="${TEX_LIVE_DOCKER_IMAGE:-$TEXLIVE_IMAGE}"
  ALL_TEX_LIVE_DOCKER_IMAGES="${ALL_TEX_LIVE_DOCKER_IMAGES:-$TEXLIVE_IMAGE}"
  if [[ -z "${ALL_TEX_LIVE_DOCKER_IMAGE_NAMES:-}" ]]; then
    local names="" img
    for img in $(echo "$ALL_TEX_LIVE_DOCKER_IMAGES" | tr ',' ' '); do
      local tag="${img##*:}"
      names+="${names:+, }TeXLive ${tag%%.*}"
    done
    ALL_TEX_LIVE_DOCKER_IMAGE_NAMES="$names"
  fi

  # --- sandboxed compiles host dirs (visible inside the app container) ---
  SANDBOXED_COMPILES_HOST_DIR="${SANDBOXED_COMPILES_HOST_DIR:-$OVERLEAF_DATA_PATH/data/compiles}"
  COMPILES_HOST_DIR="$SANDBOXED_COMPILES_HOST_DIR"
  COMPILES_CACHE_HOST_DIR="${COMPILES_CACHE_HOST_DIR:-$OVERLEAF_DATA_PATH/data/cache}"
  SYNCTEX_BIN_HOST_PATH="${SYNCTEX_BIN_HOST_PATH:-$OVERLEAF_DATA_PATH/bin/synctex}"

  # --- nginx ---
  if [[ "$NGINX_ENABLED" == "true" ]]; then
    if [[ -z "${OVERLEAF_TRUSTED_PROXY_IPS:-}" ]]; then
      OVERLEAF_TRUSTED_PROXY_IPS="loopback,172.16.0.0/12"
      warning "NGINX_ENABLED=true and OVERLEAF_TRUSTED_PROXY_IPS is unset; defaulting to '$OVERLEAF_TRUSTED_PROXY_IPS'. Set it explicitly in config/variables.env."
    fi
    OVERLEAF_SECURE_COOKIE="true"
  fi
}

function build_compose_flags() {
  local lib="$AYAKALEA_TOOLKIT_ROOT/lib/compose"
  COMPOSE_FLAGS=()
  COMPOSE_FLAGS+=(-f "$lib/ayakalea.yml")
  [[ "$MONGO_ENABLED" == "true" ]] && COMPOSE_FLAGS+=(-f "$lib/mongo.yml")
  [[ "$REDIS_ENABLED" == "true" ]] && COMPOSE_FLAGS+=(-f "$lib/redis.yml")
  [[ "$GIT_BRIDGE_ENABLED" == "true" ]] && COMPOSE_FLAGS+=(-f "$lib/git-bridge.yml")
  [[ "$SEAWEEDFS_ENABLED" == "true" ]] && COMPOSE_FLAGS+=(-f "$lib/seaweedfs.yml")
  if [[ "$NGINX_ENABLED" == "true" ]]; then
    COMPOSE_FLAGS+=(-f "$lib/nginx.yml")
  else
    COMPOSE_FLAGS+=(-f "$lib/ayakalea-ports.yml")
  fi
  [[ "$SIBLING_CONTAINERS_ENABLED" == "true" ]] && COMPOSE_FLAGS+=(-f "$lib/sibling-containers.yml")
  [[ -n "$OVERLEAF_LOG_PATH" ]] && COMPOSE_FLAGS+=(-f "$lib/logging.yml")
  if [[ -f "$AYAKALEA_TOOLKIT_ROOT/config/docker-compose.override.yml" ]]; then
    COMPOSE_FLAGS+=(-f "$AYAKALEA_TOOLKIT_ROOT/config/docker-compose.override.yml")
  fi
  return 0
}

function ensure_network() {
  docker network inspect "ayaka-network" >/dev/null 2>&1 || \
    docker network create "ayaka-network" >/dev/null || \
    ayakalea_die "could not create Docker network 'ayaka-network'"
}

function ensure_data_dirs() {
  mkdir -p "$AYAKALEA_TOOLKIT_ROOT/data/overleaf"
  if [[ "$MONGO_ENABLED" == "true" ]]; then mkdir -p "$MONGO_DATA_PATH"; fi
  if [[ "$REDIS_ENABLED" == "true" ]]; then mkdir -p "$REDIS_DATA_PATH"; fi
  if [[ "$GIT_BRIDGE_ENABLED" == "true" ]]; then mkdir -p "$GIT_BRIDGE_DATA_PATH"; fi
  if [[ "$SEAWEEDFS_ENABLED" == "true" ]]; then
    mkdir -p "$SEAWEEDFS_DATA_PATH/master" "$SEAWEEDFS_DATA_PATH/volume" "$SEAWEEDFS_DATA_PATH/filer"
  fi
}

function export_compose_vars() {
  export PROJECT_NAME CONFIG_DIR
  export OVERLEAF_DATA_PATH OVERLEAF_LISTEN_IP OVERLEAF_PORT
  export MONGO_URL OVERLEAF_MONGO_URL MONGO_DATA_PATH MONGO_IMAGE
  export REDIS_HOST REDIS_PORT REDIS_DATA_PATH REDIS_IMAGE REDIS_COMMAND
  export OVERLEAF_REDIS_HOST
  export GIT_BRIDGE_ENABLED GIT_BRIDGE_DATA_PATH GIT_BRIDGE_IMAGE GIT_BRIDGE_LOG_LEVEL
  export SEAWEEDFS_ENABLED SEAWEEDFS_DATA_PATH SEAWEEDFS_IMAGE
  export SEAWEEDFS_S3_HOST SEAWEEDFS_S3_PORT
  export NGINX_ENABLED NGINX_CONFIG_PATH NGINX_HTTP_PORT NGINX_HTTP_LISTEN_IP
  export NGINX_TLS_LISTEN_IP NGINX_IMAGE TLS_PORT TLS_PRIVATE_KEY_PATH TLS_CERTIFICATE_PATH
  export AYAKALEA_IMAGE
  export DOCKER_SOCKET_PATH
  export SANDBOXED_COMPILES_HOST_DIR COMPILES_HOST_DIR COMPILES_CACHE_HOST_DIR SYNCTEX_BIN_HOST_PATH
  export TEX_LIVE_DOCKER_IMAGE ALL_TEX_LIVE_DOCKER_IMAGES ALL_TEX_LIVE_DOCKER_IMAGE_NAMES
  export OVERLEAF_TRUSTED_PROXY_IPS OVERLEAF_SECURE_COOKIE
  export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
  if [[ -n "$OVERLEAF_LOG_PATH" ]]; then export OVERLEAF_LOG_PATH; fi
  return 0
}

function print_debug_info() {
  if [[ "${RC_DEBUG:-null}" != "null" ]]; then
    echo ">>>>>>VARS>>>>>>" >&2
    echo "$(set -o posix; set)" >&2
    echo "<<<<<<<<<<<<<<<<" >&2
    echo ">>>>COMPOSE-ARGS>>>>" >&2
    echo "-p $PROJECT_NAME" >&2
    echo "${COMPOSE_FLAGS[@]}" >&2
    echo "$@" >&2
    echo "<<<<<<<<<<<<<<<<<<" >&2
  fi
}

# Load config, resolve everything, build compose flags. Call once.
function ayakalea_prepare() {
  CONFIG_DIR="$AYAKALEA_TOOLKIT_ROOT/config"
  apply_defaults
  source_config_files
  migrate_legacy_image_settings
  resolve_derived_vars
  build_compose_flags
  export_compose_vars
}

# Run docker compose with the toolkit project + file flags (does not exec)
function ayakalea_compose() {
  if docker compose version >/dev/null 2>&1; then
    docker compose -p "$PROJECT_NAME" "${COMPOSE_FLAGS[@]}" "$@"
  elif command -v docker-compose >/dev/null 2>&1; then
    warning "docker-compose v1 is deprecated; install the Docker Compose v2 plugin"
    docker-compose -p "$PROJECT_NAME" "${COMPOSE_FLAGS[@]}" "$@"
  else
    ayakalea_die "Could not find Docker Compose"
  fi
}
