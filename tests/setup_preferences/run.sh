#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"
ubuntu_setup="$repo_root/tools/setup_ubuntu.sh"
macos_setup="$repo_root/tools/setup_macos.sh"
ghostty_config="$repo_root/dotfiles/ghostty/config"

if [ ! -f "$ghostty_config" ] ||
	[ "$(grep -Fxc 'copy-on-select = clipboard' "$ghostty_config")" -ne 1 ]; then
	printf '%s\n' 'FAIL: managed Ghostty config does not copy selections to the system clipboard'
	exit 1
fi

# shellcheck disable=SC2016 # The production variable references are intentional.
if ! grep -Fq \
	'local ghostty_config_dir="$HOME/Library/Application Support/com.mitchellh.ghostty"' \
	"$macos_setup" ||
	! grep -Fq \
		'cp "$PROFILE_DIR/dotfiles/ghostty/config" "$ghostty_config_dir/config.ghostty"' \
		"$macos_setup" ||
	! grep -Fq \
		'rm -f "$HOME/.config/ghostty/config"' \
		"$macos_setup"; then
	printf '%s\n' 'FAIL: macOS setup does not install the managed Ghostty config at its canonical path'
	exit 1
fi

# shellcheck disable=SC2016 # The production variable references are intentional.
if ! grep -Fq \
	'cp $PROFILE_DIR/dotfiles/ghostty/config $HOME/.config/ghostty/config' \
	"$ubuntu_setup"; then
	printf '%s\n' 'FAIL: Ubuntu setup does not install the managed Ghostty config'
	exit 1
fi

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

for locale_setting in \
	'sudo locale-gen en_GB.UTF-8' \
	'sudo update-locale LANG=en_GB.UTF-8' \
	"gsettings set org.gnome.system.locale region 'en_GB.UTF-8'"; do
	if ! grep -Fq "$locale_setting" "$ubuntu_setup"; then
		printf 'FAIL: Ubuntu setup is missing locale setting: %s\n' "$locale_setting"
		exit 1
	fi
done

if ! grep -Fqx $'\t\tconfigure_locale' "$ubuntu_setup"; then
	printf '%s\n' 'FAIL: Ubuntu setup does not run locale configuration'
	exit 1
fi

printf '%s\n' 'PASS: terminal input, Ghostty, and locale preferences are configured'
