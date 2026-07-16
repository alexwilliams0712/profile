#!/bin/bash

sudo -v

if [ "$(uname)" = "Darwin" ]; then
	# setup_macos installs/updates the Command Line Tools after starting the
	# sudo keepalive. Running softwareupdate here used to happen before that
	# keepalive and could cause another password prompt later in the setup.
	:
elif ! command -v git >/dev/null 2>&1; then
	echo "git is not installed, installing git."
	sudo apt-get update
	sudo apt-get install -y git
fi

# Pull latest version of this repo (non-fatal on first run / auth issues).
# Apple's /usr/bin/git is only a launcher until the Command Line Tools exist.
if { [ "$(uname)" != "Darwin" ] || xcode-select -p &>/dev/null; } && GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND='ssh -o BatchMode=yes -o ConnectTimeout=10' git fetch origin 2>/dev/null; then
	git reset --hard origin/main
	git checkout main
	GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND='ssh -o BatchMode=yes -o ConnectTimeout=10' git pull
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
