#!/bin/bash

IMAGE="private/openclaw-cb"
DATE=$(date +%Y.%m.%d)
TIME=$(date +%H%M)
TAG="${1:-$DATE}-$TIME"

echo "Starte build $TAG"

docker build \
  --build-arg OPENCLAW_DOCKER_APT_PACKAGES="jq nano python3-pip xauth" \
  --build-arg OPENCLAW_INSTALL_BROWSER=1 \
  --shm-size=1g -t ${IMAGE}:${TAG} -t ${IMAGE}:latest .

echo "Build beendet - Tag: $TAG"
