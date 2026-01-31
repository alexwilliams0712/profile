#!/bin/bash
echo "Setup running"
mkdir -p $HOME/CODE
export CODE_ROOT=$HOME/CODE
export PROJECT_ROOT=$HOME/profile
export PATH="/usr/local/bin:$PATH"
export PATH="/usr/local/sbin:$PATH"
export PATH="$HOME/.local/bin:$PATH"
# Ensure Homebrew is on PATH for Apple Silicon and Intel Macs
eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv 2>/dev/null || true)"
export DEFAULT_PYTHON_VERSION="3.14"
export PROFILE_DIR=$(pwd)
export ARCHITECTURE=$(uname -m)
exit_code=0
set -e
set -o pipefail

handle_error() {
	echo "An error occurred on line $1"
}
trap 'handle_error $LINENO' ERR

print_function_name() {
	log "\033[1;36mExecuting function: ${FUNCNAME[1]}\033[0m"
}

log() {
	echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

ensure_directory() {
	cd $PROFILE_DIR
}

copy_dotfiles() {
	print_function_name
	mkdir -p "$HOME/.config"
	cp "$PROFILE_DIR/dotfiles/.profile" "$HOME/.profile"
	cp "$PROFILE_DIR/VERSION" "$HOME/BASH_PROFILE_VERSION"
	cp "$PROFILE_DIR/dotfiles/.bashrc" "$HOME/.bashrc"
	cp "$PROFILE_DIR/dotfiles/.prettierrc" "$HOME/.prettierrc"
	cp "$PROFILE_DIR/dotfiles/.bash_aliases" "$HOME/.bash_aliases"

	# Disable custom prefs folder (fragile — breaks if repo path changes)
	defaults write com.googlecode.iterm2 LoadPrefsFromCustomFolder -bool false

	# Minimal window style (no title bar, matches terminator's show_titlebar=False)
	defaults write com.googlecode.iterm2 TabStyleWithAutomaticOption -int 5

	# Disable per-pane title bars (matches terminator's show_titlebar=False)
	defaults write com.googlecode.iterm2 ShowPaneTitles -bool false

	# Suppress quit and close-session confirmation dialogs
	defaults write com.googlecode.iterm2 PromptOnQuit -bool false
	defaults write com.googlecode.iterm2 OnlyWhenMoreTabs -bool false

	# Dim inactive split panes for visual focus indication
	defaults write com.googlecode.iterm2 DimInactiveSplitPanes -bool true

	# Global key bindings (override default menu shortcuts)
	# Cmd+O: Split Horizontally, Cmd+E: Split Vertically, Cmd+W: Close Pane
	local plist="$HOME/Library/Preferences/com.googlecode.iterm2.plist"
	/usr/libexec/PlistBuddy -c "Delete :GlobalKeyMap" "$plist" 2>/dev/null || true
	/usr/libexec/PlistBuddy -c "Add :GlobalKeyMap dict" "$plist"
	/usr/libexec/PlistBuddy -c "Add :GlobalKeyMap:0x1f-0x100000 dict" "$plist"
	/usr/libexec/PlistBuddy -c "Add :GlobalKeyMap:0x1f-0x100000:Action integer 25" "$plist"
	/usr/libexec/PlistBuddy -c "Add :GlobalKeyMap:0x1f-0x100000:Text string ''" "$plist"
	/usr/libexec/PlistBuddy -c "Add :GlobalKeyMap:0xe-0x100000 dict" "$plist"
	/usr/libexec/PlistBuddy -c "Add :GlobalKeyMap:0xe-0x100000:Action integer 26" "$plist"
	/usr/libexec/PlistBuddy -c "Add :GlobalKeyMap:0xe-0x100000:Text string ''" "$plist"
	/usr/libexec/PlistBuddy -c "Add :GlobalKeyMap:0xd-0x100000 dict" "$plist"
	/usr/libexec/PlistBuddy -c "Add :GlobalKeyMap:0xd-0x100000:Action integer 36" "$plist"
	/usr/libexec/PlistBuddy -c "Add :GlobalKeyMap:0xd-0x100000:Text string ''" "$plist"

	# Set the "Terminator Style" dynamic profile as the default profile
	defaults write com.googlecode.iterm2 "Default Bookmark Guid" -string "terminator-style-profile"

	# Install Dynamic Profile (terminator-like appearance)
	local iterm2_profiles_dir="$HOME/Library/Application Support/iTerm2/DynamicProfiles"
	mkdir -p "$iterm2_profiles_dir"
	cp "$PROFILE_DIR/dotfiles/iterm2/terminator-style.json" "$iterm2_profiles_dir/terminator-style.json"

	# Case-insensitive tab completion
	if [ ! -f "$HOME/.inputrc" ] || ! grep -q 'completion-ignore-case' "$HOME/.inputrc" 2>/dev/null; then
		echo 'set completion-ignore-case On' >>"$HOME/.inputrc"
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

	# Apply values collected by collect_user_input
	[ ! -z "$GIT_USER_NAME" ] && git config --global user.name "$GIT_USER_NAME"
	[ ! -z "$GIT_USER_EMAIL" ] && git config --global user.email "$GIT_USER_EMAIL"
	[ ! -z "$GIT_USER_PHONE" ] && git config --global user.phonenumber "$GIT_USER_PHONE"
}

install_homebrew() {
	print_function_name
	if ! command -v brew >/dev/null 2>&1; then
		log "Installing Homebrew..."
		/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

		# Add Homebrew to PATH for Apple Silicon Macs
		if [[ $(uname -m) == 'arm64' ]]; then
			echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >>$HOME/.zprofile
			eval "$(/opt/homebrew/bin/brew shellenv)"
		fi
	fi

	# Re-evaluate brew shellenv to ensure PATH includes Homebrew for the
	# rest of this script (covers both fresh install and existing install)
	eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv 2>/dev/null || true)"

	# Set HOMEBREW_NO_AUTO_UPDATE to prevent brew from running git updates
	# during individual installs (we handle updates explicitly)
	export HOMEBREW_NO_AUTO_UPDATE=1

	# Ensure Homebrew's git uses the credential helper
	export HOMEBREW_NO_INSTALL_FROM_API=0
}

install_packages() {
	print_function_name
	# Remove stale/deprecated taps that cause git errors or auth prompts
	local stale_taps=("hashicorp/tap" "homebrew/cask-drivers" "homebrew/cask-versions" "ubuntu/microk8s")
	for tap in "${stale_taps[@]}"; do
		if brew tap | grep -q "$tap"; then
			log "Removing stale tap: $tap"
			brew untap "$tap" 2>/dev/null || true
		fi
	done

	log "Updating Homebrew..."
	# brew update can fail on stale taps — not critical
	brew update || log "Warning: brew update had errors, continuing..."
	log "Installing packages from Brewfile..."
	brew bundle --no-lock --file="$PROFILE_DIR/tools/Brewfile"
	brew upgrade
	brew cleanup
}

setup_bash() {
	print_function_name
	# macOS ships with bash 3.2 (GPLv2). Homebrew installs bash 5+ which is
	# needed for associative arrays and other features used in .bash_aliases.
	local brew_bash="/opt/homebrew/bin/bash"
	if [ -f "$brew_bash" ]; then
		if ! grep -q "$brew_bash" /etc/shells 2>/dev/null; then
			log "Adding Homebrew bash to /etc/shells"
			echo "$brew_bash" | sudo tee -a /etc/shells
		fi
		if [ "$SHELL" != "$brew_bash" ]; then
			log "Setting Homebrew bash as default shell"
			sudo chsh -s "$brew_bash" "$USER"
		fi
	fi

	# macOS Terminal/iTerm2 open login shells which source .bash_profile,
	# not .bashrc. Ensure .bash_profile sources .bashrc.
	if [ ! -f "$HOME/.bash_profile" ] || ! grep -q '.bashrc' "$HOME/.bash_profile" 2>/dev/null; then
		log "Configuring .bash_profile to source .bashrc"
		echo '[ -f ~/.bashrc ] && source ~/.bashrc' >>"$HOME/.bash_profile"
	fi
}

setup_python() {
	print_function_name
	log "Setting up Python environment..."

	# Set build flags so pyenv can find Homebrew dependencies
	# (openssl, readline, sqlite3, zlib, tcl-tk are keg-only on macOS)
	export LDFLAGS="-L$(brew --prefix openssl)/lib -L$(brew --prefix readline)/lib -L$(brew --prefix sqlite3)/lib -L$(brew --prefix zlib)/lib"
	export CPPFLAGS="-I$(brew --prefix openssl)/include -I$(brew --prefix readline)/include -I$(brew --prefix sqlite3)/include -I$(brew --prefix zlib)/include"
	export PKG_CONFIG_PATH="$(brew --prefix openssl)/lib/pkgconfig:$(brew --prefix readline)/lib/pkgconfig:$(brew --prefix sqlite3)/lib/pkgconfig:$(brew --prefix zlib)/lib/pkgconfig"

	export PYENV_ROOT="$HOME/.pyenv"
	export PATH="$PYENV_ROOT/bin:$PATH"
	if command -v pyenv >/dev/null 2>&1; then
		eval "$(pyenv init --path)"
		eval "$(pyenv init -)"
	fi

	pyenv install -s $DEFAULT_PYTHON_VERSION
	pyenv global $DEFAULT_PYTHON_VERSION

	# uv is installed via Homebrew

	# Install base packages
	uv pip install pip-tools psutil

	# Create a default venv if needed
	if [ ! -d "$HOME/.venv" ]; then
		uv venv "$HOME/.venv"
	fi
}

install_rust() {
	print_function_name
	# rustup is installed via Homebrew
	rustup-init -y --default-toolchain stable
	source "$HOME/.cargo/env"
	rustup update stable
	rustup install nightly
	rustup component add rustfmt clippy
	rustup update stable
}

install_node() {
	print_function_name
	# Node is installed via Homebrew
	if command -v node >/dev/null 2>&1; then
		node -v
		npm -v
		# Set npm global prefix to match PATH in .bashrc (~/.npm-global/bin)
		mkdir -p "$HOME/.npm-global"
		npm config set prefix "$HOME/.npm-global"
		npm install -g wscat json5 fracturedjsonjs
	else
		log "Node not found, skipping npm global installs"
	fi
}

go_installs() {
	print_function_name
	# scc is installed via Homebrew
	go install github.com/dim13/otpauth@latest
}

install_go() {
	print_function_name
	# Go is installed via Homebrew
	if command -v go >/dev/null 2>&1; then
		go version
		go_installs
	else
		log "Go not found, skipping go installs"
	fi
}

setup_docker() {
	print_function_name
	log "Setting up Docker..."
	mkdir -p ~/.docker/cli-plugins

	# Symlink docker-compose from Homebrew if available
	if [ -f /opt/homebrew/opt/docker-compose/bin/docker-compose ]; then
		ln -sfn /opt/homebrew/opt/docker-compose/bin/docker-compose ~/.docker/cli-plugins/docker-compose
	fi

	# Start Docker Desktop
	if [ -d "/Applications/Docker.app" ]; then
		open -a Docker
	fi
}

install_espanso() {
	print_function_name
	# Espanso is installed via Homebrew cask
	if command -v espanso >/dev/null 2>&1; then
		mkdir -p "$(espanso path config)/match"
		cp "$PROFILE_DIR/dotfiles/espanso_match_file.yml" "$(espanso path config)/match/base.yml"
		espanso --version
	else
		log "espanso not found, skipping config"
	fi
}

install_tailscale() {
	print_function_name
	# Tailscale is installed via Homebrew cask. The cask installs the GUI app
	# but does not put the CLI on PATH. We need to:
	# 1. Open the app so the system extension can be activated
	# 2. Create a symlink so `tailscale` works from the terminal
	local tailscale_cli="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
	local symlink_target="/usr/local/bin/tailscale"

	if [ -d "/Applications/Tailscale.app" ]; then
		log "Opening Tailscale.app (required to activate system extension)..."
		open -a Tailscale

		# Create CLI symlink if not already present
		if [ ! -L "$symlink_target" ] && [ -f "$tailscale_cli" ]; then
			log "Creating CLI symlink: $symlink_target -> $tailscale_cli"
			sudo ln -sf "$tailscale_cli" "$symlink_target"
		fi

		if command -v tailscale >/dev/null 2>&1; then
			tailscale version
		else
			log "Tailscale CLI will be available after restarting your shell."
		fi
	else
		log "Tailscale.app not found in /Applications. Verify brew cask install succeeded."
	fi
}

install_ai() {
	print_function_name

	# Claude Code and Gemini CLI are installed via Homebrew

	# Install ChatGPT CLI (shell-gpt)
	log "Installing ChatGPT CLI (shell-gpt)..."
	if command -v sgpt >/dev/null 2>&1; then
		log "shell-gpt already installed, upgrading..."
	fi
	uv pip install -U shell-gpt

	log "AI CLI tools installation complete"
}

install_webtools() {
	print_function_name
	# shfmt, shellcheck, and k9s are installed via Homebrew
	curl -sS https://webi.sh/awless | sh
}

exit_script() {
	print_function_name
	if [[ exit_code -eq 0 ]]; then
		ensure_directory
		source ~/.bashrc
		echo "==============================="
		echo "       Setup Complete          "
		echo "==============================="
	else
		echo "==============================="
		echo "       Setup Failed            "
		echo "==============================="
	fi
}

main() {
	collect_user_input

	failed_functions=()

	run_function() {
		local func_name=$1
		if ! $func_name; then
			failed_functions+=("$func_name")
			echo "Warning: $func_name failed, continuing with next function..."
		fi
	}

	run_function copy_dotfiles
	run_function set_git_config
	run_function install_homebrew
	run_function install_packages
	run_function setup_bash
	run_function setup_python
	run_function install_rust
	run_function install_node
	run_function install_go
	run_function setup_docker
	run_function install_espanso
	run_function install_tailscale
	run_function install_webtools
	run_function install_ai

	# Report failures if any
	if [ ${#failed_functions[@]} -ne 0 ]; then
		echo -e "\n\033[1;91mThe following functions failed:\033[0m"
		printf '\033[1;91m%s\033[0m\n' "${failed_functions[@]}"
		echo -e "\n\033[1;91mPlease check the above functions and try running them individually.\033[0m"
	fi

	exit_script
}
main
