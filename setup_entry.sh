#!/bin/bash

sudo -v
# Keep sudo alive in the background — refresh every 60 seconds until this
# script (and its children) exit.
(while true; do sudo -n true; sleep 60; done) 2>/dev/null &
SUDO_KEEPALIVE_PID=$!
trap 'kill $SUDO_KEEPALIVE_PID 2>/dev/null' EXIT

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

# Set up credential helper before fetching (macOS needs osxkeychain for HTTPS)
if [ "$(uname)" = "Darwin" ]; then
	git config --global credential.helper osxkeychain
fi

# Pull latest version of this repo (non-fatal on first run / auth issues)
if git fetch origin 2>/dev/null; then
	git reset --hard origin/main
	git checkout main
	git pull
else
	echo "Warning: could not fetch from remote, continuing with local copy."
fi

os_name="$(uname)"

if [ "$os_name" = "Darwin" ]; then
	bash tools/setup_macos.sh
elif [ "$os_name" = "Linux" ]; then
	bash tools/setup_ubuntu.sh
else
	source tools/setup_macos.sh
fi
