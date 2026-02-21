#!/usr/bin/env bash
set -euo pipefail
export GIT_PAGER=cat
exec 2>&1

STASH_NAME="autoupdate-local-$(date -Is)"

# Konfiguration via /etc/openclaw/deploy.env (systemd EnvironmentFile)
: "${GITHUB_TOKEN:?GITHUB_TOKEN not set}"
: "${OWNER:-chrisblech}"
: "${REPO:-openclaw}"
: "${REPO_ROOT:?REPO_ROOT not set}"

ORIGIN_URL="${ORIGIN_URL:-https://github.com/${OWNER}/${REPO}.git}"
LOCK_FILE="${LOCK_FILE:-/run/openclaw/deploy.lock}"

UPSTREAM_LATEST_URL="${UPSTREAM_LATEST_URL:-https://github.com/openclaw/openclaw/releases/latest}"

log() { echo "[$(date +%F_%X)] $*"; }

# Prevent parallel runs
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  log "Another deploy is already running. Exiting."
  exit 0
fi

log "Determine latest upstream release tag..."
TAG="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "${UPSTREAM_LATEST_URL}" | sed 's#.*/tag/##')"
VERSION_TAG="${TAG}-cb"

log "Upstream latest tag: ${TAG}"
log "Expecting tag:       ${VERSION_TAG}"

log "Trigger GitHub workflow via repository_dispatch..."
curl -fsSL -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "User-Agent: openclaw-vps" \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  "https://api.github.com/repos/${OWNER}/${REPO}/dispatches" \
  -d '{"event_type":"vps_rebase_request"}' >/dev/null

# Ensure repo exists
if [ ! -d "${REPO_ROOT}/.git" ]; then
  log "Cloning repo to ${REPO_ROOT}..."
  mkdir -p "${REPO_ROOT}"
  git clone "${ORIGIN_URL}" "${REPO_ROOT}"
fi

cd "${REPO_ROOT}"

log "Waiting for tag to appear on origin..."
for _ in $(seq 1 180); do  # 180 * 2s = 6min
  if git ls-remote --exit-code --tags origin "refs/tags/${VERSION_TAG}" >/dev/null 2>&1; then
    log "Tag exists: ${VERSION_TAG}"
    break
  fi
  sleep 2
done

if ! git ls-remote --exit-code --tags origin "refs/tags/${VERSION_TAG}" >/dev/null 2>&1; then
  log "ERROR: Tag did not appear: ${VERSION_TAG}"
  exit 1
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
  log "Lokale Änderungen gefunden -> stash (${STASH_NAME})"
  git stash push -u -m "${STASH_NAME}"
  STASHED=1
else
  STASHED=0
fi

log "Fetch + checkout latest version..."
git fetch origin tag ${VERSION_TAG}
git checkout --force ${VERSION_TAG}

if [ "${STASHED}" -eq 1 ]; then
  log "Versuche lokale Änderungen wieder anzuwenden (stash pop)..."
  if git stash pop; then
    log "Stash erfolgreich angewendet."
  else
    log "KONFLIKT beim Anwenden des Stash!"
    log "Status:"
    git status --porcelain=v1 || true
    log "Stash bleibt erhalten. Du kannst ihn manuell anwenden:"
    log "  git stash list"
    log "  git stash apply stash@{0}"
    exit 1
  fi
fi

log "Deploy script finished. Starting build..."

exec ./build.sh ${VERSION_TAG}
