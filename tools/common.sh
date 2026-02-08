#!/bin/bash
# Shared functions used by both setup_macos.sh and setup_ubuntu.sh

export DEFAULT_PYTHON_VERSION="3.14"

handle_error() {
	echo "An error occurred on line $1"
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
	git config --global http.sslVerify false
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

	# Use delta as the pager for diff/log/show if available
	if command -v delta >/dev/null 2>&1; then
		git config --global core.pager delta
		git config --global interactive.diffFilter 'delta --color-only'
		git config --global delta.navigate true
		git config --global delta.side-by-side true
		git config --global delta.line-numbers true
		git config --global merge.conflictStyle zdiff3
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

install_pyenv() {
	print_function_name
	local os_type
	os_type="$(uname -s)"

	# Platform-specific pre-requisites
	if [ "$os_type" = "Darwin" ]; then
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
	else
		for pyver in $DEFAULT_PYTHON_VERSION 3.13 3.12 3.11; do
			# Find the latest available patch for this major.minor
			local latest
			latest=$(pyenv install --list | tr -d ' ' | grep -E "^${pyver}\.[0-9]+$" | sort -V | tail -1)
			if [ -z "$latest" ]; then
				log "No available patch found for $pyver, skipping"
				continue
			fi
			# Check what's already installed for this major.minor
			local installed
			installed=$(pyenv versions --bare | grep -E "^${pyver}\.[0-9]+$" | sort -V | tail -1)
			if [ "$installed" = "$latest" ]; then
				log "Python $latest already installed, skipping"
				continue
			fi
			if [ -n "$installed" ]; then
				log "Upgrading Python $pyver: $installed -> $latest"
			else
				log "Installing Python $latest"
			fi
			pyenv install -f "$latest"
		done
	fi
	pyenv global $DEFAULT_PYTHON_VERSION

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

exit_script() {
	print_function_name
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
