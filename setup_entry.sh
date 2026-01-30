#!/bin/bash

sudo -v
if ! command -v git >/dev/null 2>&1; then
	if [ "$(uname)" = "Darwin" ]; then
		echo "git is not installed. Installing Xcode Command Line Tools..."
		xcode-select --install
		echo "Please re-run this script after Xcode Command Line Tools installation completes."
		exit 1
	else
		echo "git is not installed, installing git."
		sudo apt-get update
		sudo apt-get install -y git
	fi
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
	source tools/setup_macos.sh
fi
