#!/bin/bash

IMAGE="private/openclaw-cb"
DATE=$(date +%Y.%m.%d)
TIME=$(date +%H%M)
TAG="${1:-$DATE}-$TIME"

echo "aktiviere snd-aloop auf dem Host..."
modprobe snd-aloop
echo snd-aloop | tee /etc/modules-load.d/snd-aloop.conf
$TELEFON="alsa-utils pulseaudio ffmpeg sox baresip"
# $TEL_ADDON="libsox-fmt-all baresip-modules libasound2 pulseaudio-utils python3-venv"

echo "Starte build $TAG"

docker build \
  --build-arg OPENCLAW_DOCKER_APT_PACKAGES="jq nano python3-pip xauth $TELEFON" \
  --build-arg OPENCLAW_INSTALL_BROWSER=1 \
  --shm-size=1g -t ${IMAGE}:${TAG} -t ${IMAGE}:latest .

echo "Build beendet - Tag: $TAG"
