#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"
ubuntu_setup="$repo_root/tools/setup_ubuntu.sh"
macos_setup="$repo_root/tools/setup_macos.sh"

# shellcheck disable=SC2016 # The literal Readline directive is intentional.
if ! grep -Fxq '$include /etc/inputrc' "$repo_root/dotfiles/.inputrc" ||
	! grep -Fxq 'set completion-ignore-case on' "$repo_root/dotfiles/.inputrc"; then
	printf '%s\n' 'FAIL: managed inputrc does not enable case-insensitive completion'
	exit 1
fi

for setup in "$ubuntu_setup" "$macos_setup"; do
	# shellcheck disable=SC2016 # The production variable references are intentional.
	if ! grep -Fq 'cp "$PROFILE_DIR/dotfiles/.inputrc" "$HOME/.inputrc"' "$setup"; then
		printf 'FAIL: %s does not install the managed inputrc\n' "$setup"
		exit 1
	fi
done

if grep -Fq '/etc/inputrc' "$ubuntu_setup"; then
	printf '%s\n' 'FAIL: Ubuntu setup still modifies the system inputrc'
	exit 1
fi

if ! grep -Fq \
	'gsettings set org.gnome.desktop.interface gtk-enable-primary-paste true' \
	"$ubuntu_setup"; then
	printf '%s\n' 'FAIL: Ubuntu setup does not enable middle-click paste'
	exit 1
fi

printf '%s\n' 'PASS: terminal input preferences are configured'
