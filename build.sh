#!/bin/bash

IMAGE="private/openclaw-cb"
DATE=$(date +%Y.%m.%d)
TIME=$(date +%H%M)
TAG="${1:-$DATE}-$TIME"

get_latest_github_release_version() {
  local latest_url="https://github.com/$1/releases/latest"
  local tag
  tag="$(
    curl -fsSLI -o /dev/null -w '%{url_effective}' "$latest_url" \
    | sed -E 's#.*/tag/([^/?]+).*#\1#'
  )"
  printf '%s\n' "$tag"
}

echo "aktiviere snd-aloop auf dem Host..."
modprobe snd-aloop
echo snd-aloop | tee /etc/modules-load.d/snd-aloop.conf
TELEFON="alsa-utils pulseaudio ffmpeg sox baresip"

GOGCLI_TAG="$(get_latest_github_release_version "steipete/gogcli")"
GOPLACES_TAG="$(get_latest_github_release_version "steipete/goplaces")"

echo "Starte build $TAG"

docker build \
  --build-arg OPENCLAW_DOCKER_APT_PACKAGES="jq nano python3-pip python3-venv xauth $TELEFON" \
  --build-arg OPENCLAW_INSTALL_BROWSER=1 \
  --build-arg OPENCLAW_DOCKER_GOGCLI_VERSION=${GOGCLI_TAG#v} \
  --build-arg OPENCLAW_DOCKER_GOPLACES_VERSION=${GOPLACES_TAG#v} \
  --shm-size=1g -t ${IMAGE}:${TAG} -t ${IMAGE}:latest .

echo "Build beendet - Tag: $TAG"
