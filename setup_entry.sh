#!/bin/bash

sudo -v
# Keep sudo alive in the background — refresh every 10 seconds until this
# script (and its children) exit.
(while true; do sudo -n true; sleep 10; done) 2>/dev/null &
SUDO_KEEPALIVE_PID=$!
trap 'kill $SUDO_KEEPALIVE_PID 2>/dev/null' EXIT

if [ "$(uname)" = "Darwin" ]; then
	# Ensure Xcode Command Line Tools are installed and up to date
	if ! xcode-select -p &>/dev/null; then
		echo "Installing Xcode Command Line Tools..."
		xcode-select --install
		echo "Please re-run this script after installation completes."
		exit 1
	fi
	# Check for CLT updates (e.g. after a macOS upgrade)
	clt_update=$(softwareupdate --list 2>&1 | grep -i "command line tools" || true)
	if [ -n "$clt_update" ]; then
		echo "Updating Command Line Tools..."
		softwareupdate --install --all
	fi
elif ! command -v git >/dev/null 2>&1; then
	echo "git is not installed, installing git."
	sudo apt-get update
	sudo apt-get install -y git
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
