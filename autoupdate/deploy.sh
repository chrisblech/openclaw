#!/usr/bin/env bash
set -euo pipefail

# Konfiguration via /etc/openclaw/deploy.env (systemd EnvironmentFile)
: "${GITHUB_TOKEN:?GITHUB_TOKEN not set}"
: "${OWNER:-chrisblech}"
: "${REPO:-openclaw}"
: "${REPO_ROOT:?REPO_ROOT not set}"

ORIGIN_URL="${ORIGIN_URL:-https://github.com/${OWNER}/${REPO}.git}"
LOCK_FILE="${LOCK_FILE:-/run/openclaw-deploy.lock}"

UPSTREAM_LATEST_URL="${UPSTREAM_LATEST_URL:-https://github.com/openclaw/openclaw/releases/latest}"

log() { echo "[$(date -Is)] $*"; }

# Prevent parallel runs
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  log "Another deploy is already running. Exiting."
  exit 0
fi

log "Determine latest upstream release tag..."
TAG="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "${UPSTREAM_LATEST_URL}" | sed 's#.*/tag/##')"
VERSION_BRANCH="openclaw-cb-${TAG}"

log "Upstream latest tag: ${TAG}"
log "Expecting branch:    ${VERSION_BRANCH}"

log "Trigger GitHub workflow via repository_dispatch..."
curl -fsSL -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  "https://api.github.com/repos/${OWNER}/${REPO}/dispatches" \
  -d '{"event_type":"vps_rebase_request"}' >/dev/null

# Ensure repo exists
if [ ! -d "${REPO_ROOT}/.git" ]; then
  log "Cloning repo to ${REPO_ROOT}..."
  mkdir -p "${REPO_ROOT}"
  git clone "${ORIGIN_URL}" "${RREPO_ROOTR}"
fi

cd "${REPO_ROOT}"

log "Waiting for branch to appear on origin..."
for _ in $(seq 1 180); do  # 180 * 2s = 6min
  if git ls-remote --exit-code --heads origin "refs/heads/${VERSION_BRANCH}" >/dev/null 2>&1; then
    log "Branch exists: ${VERSION_BRANCH}"
    break
  fi
  sleep 2
done

if ! git ls-remote --exit-code --heads origin "refs/heads/${VERSION_BRANCH}" >/dev/null 2>&1; then
  log "ERROR: Branch did not appear: ${VERSION_BRANCH}"
  exit 1
fi

log "Fetch + checkout version branch..."
git fetch origin --prune --tags
git checkout -B "${VERSION_BRANCH}" "origin/${VERSION_BRANCH}"
git reset --hard "origin/${VERSION_BRANCH}"

# --- Build/Restart (HIER anpassen) ---
#log "Build..."
#corepack enable >/dev/null 2>&1 || true
#pnpm install --frozen-lockfile
#pnpm build

log "Deploy script finished."
