#!/bin/bash

IMAGE="private/openclaw-cb"
DATE=$(date +%Y.%m.%d)
TAG=${1:-$DATE}

echo "Starte build $TAG"

docker build \
  --build-arg OPENCLAW_DOCKER_APT_PACKAGES="chromium jq python3-pip xauth xvfb" \
  --shm-size=1g -t ${IMAGE}:${TAG} .

echo "Build beendet - Tag: $TAG"
