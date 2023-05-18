#!/bin/bash

if ! command -v git >/dev/null 2>&1; then
  echo "git is not installed, installing git."
  sudo apt-get update
  sudo apt-get install -y git
fi

git fetch origin && git reset --hard origin/main
git checkout main
git pull

os_name="$(uname)"

if [ "$os_name" = "Darwin" ]; then
    bash tools/setup_macos.sh
elif [ "$os_name" = "Linux" ]; then
    bash tools/setup_ubuntu.sh
else
    echo "Running on an unsupported OS."
fi
