#!/bin/bash
# Shared functions used by both setup_macos.sh and setup_ubuntu.sh

export DEFAULT_PYTHON_VERSION="3.14.5"

handle_error() {
	echo "An error occurred on line $1"
}

# Prime the sudo timestamp once, then keep it warm in the background so a long
# unattended install only prompts for the password a single time.
# - Idempotent: a second call is a no-op while a loop is already running.
# - set -e / pipefail safe: the priming `sudo -v` is guarded with `|| return`,
#   and the background loop's commands can't abort the parent shell.
# - The loop exits on its own once the parent script ($$) is gone, is killed by
#   the EXIT trap on error/early-exit paths, and is killed explicitly by
#   exit_script before its `exec bash -l` (which would otherwise bypass EXIT).
SUDO_KEEPALIVE_PID=""
keep_sudo_alive() {
	# Already running? Do nothing.
	if [ -n "$SUDO_KEEPALIVE_PID" ] && kill -0 "$SUDO_KEEPALIVE_PID" 2>/dev/null; then
		return 0
	fi
	# Prompt for the password once (non-fatal under set -e if the user aborts).
	sudo -v || return 1
	# Refresh the timestamp every 60s until this script's PID disappears.
	local parent_pid=$$
	while true; do
		sudo -n true 2>/dev/null || true
		sleep 60
		kill -0 "$parent_pid" 2>/dev/null || exit 0
	done &
	SUDO_KEEPALIVE_PID=$!
	# Reap the loop when the script exits (without clobbering the ERR trap).
	trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT
}

print_function_name() {
	log "\033[1;36mExecuting function: ${FUNCNAME[1]}\033[0m"
}

log() {
	echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

ensure_directory() {
	cd $PROFILE_DIR
}

# Evaluate the Homebrew shellenv matching the current architecture.
# Apple Silicon native uses /opt/homebrew, Rosetta/Intel uses /usr/local;
# fall back to the other prefix if the preferred one isn't present.
brew_shellenv() {
	if [ "$(uname -m)" = "arm64" ]; then
		eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv 2>/dev/null || true)"
	else
		eval "$(/usr/local/bin/brew shellenv 2>/dev/null || /opt/homebrew/bin/brew shellenv 2>/dev/null || true)"
	fi
}

collect_user_input() {
	# Gather all interactive input upfront so the rest of the setup is unattended
	GIT_USER_NAME=$(git config --global user.name 2>/dev/null) || GIT_USER_NAME=""
	GIT_USER_EMAIL=$(git config --global user.email 2>/dev/null) || GIT_USER_EMAIL=""
	GIT_USER_PHONE=$(git config --global user.phonenumber 2>/dev/null) || GIT_USER_PHONE=""

	if [ -z "$GIT_USER_NAME" ]; then
		read -p "Enter github username: " GIT_USER_NAME
	fi
	read -p "Enter github email address (leave blank to keep '$GIT_USER_EMAIL'): " input
	if [ ! -z "$input" ]; then
		GIT_USER_EMAIL="$input"
	fi
	read -p "Enter phone number (leave blank to keep '$GIT_USER_PHONE'): " input
	if [ ! -z "$input" ]; then
		GIT_USER_PHONE="$input"
	fi
	echo ""
	log "All input collected. Setup will now run unattended."
}

run_function() {
	local func_name=$1 exit_code=0
	if command -v gum >/dev/null 2>&1; then
		gum style --foreground 212 --bold ">>> $func_name"
		$func_name || exit_code=$?
		if [ $exit_code -ne 0 ]; then
			gum style --foreground 196 --bold "FAIL $func_name"
			failed_functions+=("$func_name")
		else
			gum style --foreground 82 --bold "<<< $func_name done"
		fi
	else
		$func_name || exit_code=$?
		if [ $exit_code -ne 0 ]; then
			failed_functions+=("$func_name")
			echo "Warning: $func_name failed, continuing with next function..."
		fi
	fi
}

set_git_config() {
	print_function_name
	git config --global core.autocrlf false
	git config --global pull.rebase false
	git config --global diff.tool bc3
	git config --global color.branch auto
	git config --global color.diff auto
	git config --global color.interactive auto
	git config --global color.status auto
	git config --global push.default simple
	git config --global merge.tool kdiff3
	git config --global difftool.prompt false
	git config --global alias.c commit
	git config --global alias.ca 'commit -a'
	git config --global alias.cm 'commit -m'
	git config --global alias.cam 'commit -am'
	git config --global alias.d diff
	git config --global alias.dc 'diff --cached'
	git config --global alias.l 'log --graph --pretty=format:"%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset" --abbrev-commit'
	git config --global merge.conflictStyle zdiff3

	# Use delta as the pager for diff/log/show if available
	if command -v delta >/dev/null 2>&1; then
		git config --global core.pager delta
		git config --global interactive.diffFilter 'delta --color-only'
		git config --global delta.navigate true
		git config --global delta.side-by-side true
		git config --global delta.line-numbers true
	fi

	# Apply values collected by collect_user_input
	if [ -n "$GIT_USER_NAME" ]; then git config --global user.name "$GIT_USER_NAME"; fi
	if [ -n "$GIT_USER_EMAIL" ]; then git config --global user.email "$GIT_USER_EMAIL"; fi
	if [ -n "$GIT_USER_PHONE" ]; then git config --global user.phonenumber "$GIT_USER_PHONE"; fi
}

copy_btop_config() {
	mkdir -p "$HOME/.config/btop/themes"
	cp "$PROFILE_DIR/dotfiles/btop/themes/armada-deep.theme" "$HOME/.config/btop/themes/armada-deep.theme"
	cp "$PROFILE_DIR/dotfiles/btop/btop.conf" "$HOME/.config/btop/btop.conf"
}

install_starship() {
	print_function_name
	curl -sS https://starship.rs/install.sh | sh -s -- -y
	if command -v starship >/dev/null 2>&1; then
		starship --version
	fi
}

install_foundry() {
	print_function_name
	# Foundry (forge, cast, anvil, chisel) via the official installer — NOT snap.
	# foundryup installs to ~/.foundry/bin (added to PATH in .bashrc).
	curl -L https://foundry.paradigm.xyz | bash
	"$HOME/.foundry/bin/foundryup"
	"$HOME/.foundry/bin/cast" --version
}

install_rust() {
	print_function_name
	# Rust via the official rustup installer (NOT Homebrew/apt). This keeps the
	# real rustup binary and its cargo/rustc proxies in ~/.cargo/bin. Installing
	# rustup from Homebrew puts the binary under /opt/homebrew and leaves the
	# ~/.cargo/bin proxies dangling whenever the formula is renamed/upgraded.
	if [ ! -x "$HOME/.cargo/bin/rustup" ]; then
		curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
	fi
	# shellcheck source=/dev/null
	source "$HOME/.cargo/env"
	rustup toolchain install nightly
	rustup component add rustfmt clippy
	rustup update stable
}

install_pyenv() {
	print_function_name
	local os_type
	os_type="$(uname -s)"

	# Platform-specific pre-requisites
	if [ "$os_type" = "Darwin" ]; then
		# Enforce native architecture — abort if running under Rosetta on Apple Silicon
		local hw_arch
		hw_arch="$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)"
		if [ "$hw_arch" = "1" ] && [ "$(uname -m)" = "x86_64" ]; then
			log "ERROR: Running under Rosetta (x86_64 translation) on Apple Silicon."
			log "Re-run this script natively: arch -arm64 bash setup_entry.sh"
			return 1
		fi

		# Force compiler to target the native architecture
		export ARCHFLAGS="-arch $(uname -m)"

		# Set build flags so pyenv can find Homebrew keg-only dependencies
		export LDFLAGS="-L$(brew --prefix openssl)/lib -L$(brew --prefix readline)/lib -L$(brew --prefix sqlite3)/lib -L$(brew --prefix zlib)/lib"
		export CPPFLAGS="-I$(brew --prefix openssl)/include -I$(brew --prefix readline)/include -I$(brew --prefix sqlite3)/include -I$(brew --prefix zlib)/include"
		export PKG_CONFIG_PATH="$(brew --prefix openssl)/lib/pkgconfig:$(brew --prefix readline)/lib/pkgconfig:$(brew --prefix sqlite3)/lib/pkgconfig:$(brew --prefix zlib)/lib/pkgconfig"
	else
		apt_upgrader
		sudo apt install -y software-properties-common
	fi

	# Install pyenv if not already present
	local pyenv_dir="$HOME/.pyenv"
	if [ -d "$pyenv_dir" ]; then
		log "The $pyenv_dir directory already exists. Remove it to reinstall."
	else
		curl https://pyenv.run | bash
	fi

	export PYENV_ROOT="$HOME/.pyenv"
	export PATH="$PYENV_ROOT/bin:$PATH"
	if command -v pyenv >/dev/null 2>&1; then
		eval "$(pyenv init --path)"
		eval "$(pyenv init -)"
	fi

	# Update pyenv plugin index (Linux-only; on macOS pyenv is managed by Homebrew)
	if [ "$os_type" != "Darwin" ]; then
		source ~/.bashrc 2>/dev/null || true
		pyenv update
		source ~/.bashrc 2>/dev/null || true
	fi

	# Install Python versions
	if [ "$os_type" = "Darwin" ]; then
		pyenv install -s $DEFAULT_PYTHON_VERSION

		# Verify the installed Python matches the native architecture
		local expected_arch
		expected_arch="$(uname -m)"
		local python_bin="$PYENV_ROOT/versions/$DEFAULT_PYTHON_VERSION/bin/python3"
		if [ -f "$python_bin" ]; then
			local binary_arch
			binary_arch="$(file "$python_bin" | grep -o 'arm64\|x86_64' | head -1)"
			if [ "$binary_arch" != "$expected_arch" ]; then
				log "ERROR: Python binary is $binary_arch but expected $expected_arch"
				log "Removing mismatched build and reinstalling..."
				pyenv uninstall -f "$DEFAULT_PYTHON_VERSION"
				pyenv install "$DEFAULT_PYTHON_VERSION"
			else
				log "Python architecture verified: $binary_arch"
			fi
		fi
	else
		# Install the pinned default version exactly as specified.
		# Only one version is installed on purpose — extra minor versions slow
		# down pyenv shim resolution (and the prompt) without much benefit.
		pyenv install -s "$DEFAULT_PYTHON_VERSION"
	fi
	pyenv global "$DEFAULT_PYTHON_VERSION"

	# Install pyenv-virtualenv plugin
	local venv_folder
	venv_folder="$(pyenv root)/plugins/pyenv-virtualenv"
	local venv_url="https://github.com/pyenv/pyenv-virtualenv.git"
	if [ ! -d "$venv_folder" ]; then
		git clone "$venv_url" "$venv_folder"
	else
		cd "$venv_folder"
		git pull "$venv_url"
	fi

	# Install uv
	if [ "$os_type" = "Darwin" ]; then
		# uv is installed via Homebrew on macOS
		:
	else
		curl -LsSf https://astral.sh/uv/install.sh | sh
	fi

	# Install base Python packages
	if command -v uv >/dev/null 2>&1; then
		uv pip install --system pip-tools psutil
	fi

	# Create a default venv if needed (macOS convention)
	if [ "$os_type" = "Darwin" ] && [ ! -d "$HOME/.venv" ]; then
		uv venv "$HOME/.venv"
	fi

	ensure_directory
}

install_ai() {
	print_function_name

	# Claude Code — official native installer. Self-contained binary, no Node
	# required; auto-detects arch (darwin/linux × arm64/x64) and self-updates.
	curl -fsSL https://claude.ai/install.sh | bash

	# OpenAI Codex CLI — official native installer (Rust binary, arch-aware).
	# Re-running upgrades in place.
	curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh

	# Gemini CLI — Google ships NO native curl/bash installer; every method
	# (Homebrew, MacPorts, conda) just wraps the npm package, so npm is the only
	# non-Homebrew path. Node is installed earlier in both setups.
	if command -v npm >/dev/null 2>&1; then
		if [ "$(uname -s)" = "Darwin" ]; then
			# macOS uses a user-owned npm prefix (~/.npm-global), so no sudo.
			npm install -g @google/gemini-cli
		else
			# Linux installs node as root (nodesource), so global needs sudo.
			sudo npm install -g @google/gemini-cli
		fi
	else
		log "npm not found, skipping Gemini CLI install"
	fi

	log "AI CLI tools installation complete"
}

exit_script() {
	print_function_name
	# Stop the sudo keepalive explicitly: the `exec bash -l` below replaces this
	# process, so the EXIT trap would never fire to reap it otherwise.
	[ -n "$SUDO_KEEPALIVE_PID" ] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
	ensure_directory
	if [ ${#failed_functions[@]} -eq 0 ]; then
		echo "==============================="
		echo "       Setup Complete          "
		echo "==============================="
	else
		echo "==============================="
		echo "       Setup Failed            "
		echo "==============================="
	fi
	exec bash -l
}

configure_vscode() {
	# Copy VS Code settings and keybindings, install extensions.
	# Expects $VSCODE_USER_DIR to be set by the caller (platform-specific path).
	print_function_name

	if ! command -v code >/dev/null 2>&1; then
		log "code CLI not found, skipping VS Code configuration"
		return 0
	fi

	local vscode_dotfiles="$PROFILE_DIR/dotfiles/vscode"

	# Create the VS Code User directory if it doesn't exist
	mkdir -p "$VSCODE_USER_DIR"

	# Copy settings and keybindings
	cp "$vscode_dotfiles/settings.json" "$VSCODE_USER_DIR/settings.json"
	log "Copied VS Code settings.json"

	cp "$vscode_dotfiles/keybindings.json" "$VSCODE_USER_DIR/keybindings.json"
	log "Copied VS Code keybindings.json"

	# Install extensions from list
	if [ -f "$vscode_dotfiles/extensions.txt" ]; then
		while IFS= read -r line; do
			# Skip comments and blank lines
			line=$(echo "$line" | xargs)
			if [ -z "$line" ] || [[ "$line" == \#* ]]; then
				continue
			fi
			code --install-extension "$line" --force 2>/dev/null || log "Failed to install extension: $line"
		done <"$vscode_dotfiles/extensions.txt"
		log "VS Code extensions installed"
	fi
}
