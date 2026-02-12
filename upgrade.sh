#!/bin/bash

LATEST_TAG=$(
  curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/openclaw/openclaw/releases/latest" \
  | sed 's#.*/tag/##'
)

git pull

echo "Stash push"
git stash

echo "Checkout $LATEST_TAG"
git checkout $LATEST_TAG

echo "Stash pop"
git stash pop

./build.sh $LATEST_TAG
