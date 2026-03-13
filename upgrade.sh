#!/bin/bash

get_latest_github_release_version() {
  local latest_url="https://github.com/$1/releases/latest"
  local tag
  tag="$(
    curl -fsSLI -o /dev/null -w '%{url_effective}' "$latest_url" \
    | sed -E 's#.*/tag/([^/?]+).*#\1#'
  )"
  printf '%s\n' "$tag"
}

UPSTREAM="openclaw/openclaw"
LATEST_TAG="$(get_latest_github_release_version $UPSTREAM)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

echo "Merge upstream $LATEST_TAG ..."

cd $SCRIPT_DIR
git remote add upstream https://github.com/$UPSTREAM.git || true
git fetch upstream --prune --tags
git merge --no-edit "$LATEST_TAG"

echo "Starte docker build..."

exec $SCRIPT_DIR/build.sh $LATEST_TAG
