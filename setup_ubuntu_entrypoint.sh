#!/bin/bash

if ! command -v git >/dev/null 2>&1; then
  echo "git is not installed, installing git."
  sudo apt-get update
  sudo apt-get install -y git
fi

git fetch origin && git reset --hard origin/main
git checkout main
git pull

source tools/setup_ubuntu.sh