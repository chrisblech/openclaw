#!/bin/bash

BASE_IMAGE="private/openclaw"
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
## Das folgende muss evtl. als "root" User auf dem Host manuell ausgeführt werden
echo snd-aloop | tee /etc/modules-load.d/snd-aloop.conf

TELEFON="alsa-utils pulseaudio ffmpeg sox baresip python3-dev"

echo "Starte build step 1 (Base image) $BASE_IMAGE:$TAG"

docker build \
  --build-arg OPENCLAW_DOCKER_APT_PACKAGES="jq nano python3-pip python3-venv xauth $TELEFON" \
  --build-arg OPENCLAW_INSTALL_BROWSER=1 \
  --shm-size=1g -t ${BASE_IMAGE}:${TAG} .

GOGCLI_TAG="$(get_latest_github_release_version "steipete/gogcli")"
GOPLACES_TAG="$(get_latest_github_release_version "steipete/goplaces")"

echo "Starte build step 2 (custom image) $IMAGE:$TAG"

docker build -f Dockerfile-cb \
  --build-arg BASE_IMAGE=$BASE_IMAGE \
  --build-arg BASE_IMAGE_TAG=$TAG \
  --build-arg OPENCLAW_DOCKER_GOGCLI_VERSION=${GOGCLI_TAG#v} \
  --build-arg OPENCLAW_DOCKER_GOPLACES_VERSION=${GOPLACES_TAG#v} \
  --shm-size=1g -t ${IMAGE}:${TAG} -t ${IMAGE}:latest .

docker image rm ${BASE_IMAGE}:${TAG}

echo "Build beendet - Tag: $TAG"
