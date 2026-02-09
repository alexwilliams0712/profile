#!/bin/bash
echo "Setup running"

mkdir -p $HOME/CODE
export CODE_ROOT=$HOME/CODE
export PROJECT_ROOT=$HOME/profile
export PATH="/usr/local/bin:$PATH"
export PATH="/usr/local/sbin:$PATH"
export PATH="$HOME/.local/bin:$PATH"
# Use the Homebrew matching the current architecture
# (Apple Silicon native uses /opt/homebrew, Rosetta/Intel uses /usr/local)
if [ "$(uname -m)" = "arm64" ]; then
	eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv 2>/dev/null || true)"
else
	eval "$(/usr/local/bin/brew shellenv 2>/dev/null || /opt/homebrew/bin/brew shellenv 2>/dev/null || true)"
fi
export PROFILE_DIR=$(pwd)
export ARCHITECTURE=$(uname -m)
set -e
set -o pipefail

sudo -v

source "$PROFILE_DIR/tools/common.sh"
trap 'handle_error $LINENO' ERR

copy_dotfiles() {
	print_function_name
	mkdir -p "$HOME/.config"
	cp "$PROFILE_DIR/dotfiles/starship.toml" "$HOME/.config/starship.toml"
	cp "$PROFILE_DIR/dotfiles/.profile" "$HOME/.profile"
	cp "$PROFILE_DIR/VERSION" "$HOME/BASH_PROFILE_VERSION"
	cp "$PROFILE_DIR/dotfiles/.bashrc" "$HOME/.bashrc"
	cp "$PROFILE_DIR/dotfiles/.prettierrc" "$HOME/.prettierrc"
	cp "$PROFILE_DIR/dotfiles/.bash_aliases" "$HOME/.bash_aliases"
	copy_btop_config

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
	# Cmd+O: Split Horizontally, Cmd+E: Split Vertically
	# Cmd+W is NOT overridden — iTerm2's default close behavior is correct
	local plist="$HOME/Library/Preferences/com.googlecode.iterm2.plist"
	/usr/libexec/PlistBuddy -c "Delete :GlobalKeyMap" "$plist" 2>/dev/null || true
	/usr/libexec/PlistBuddy -c "Add :GlobalKeyMap dict" "$plist"
	# Cmd+O (0x6f) → Split Horizontally with Current Profile (Action 25)
	/usr/libexec/PlistBuddy -c "Add :GlobalKeyMap:0x6f-0x100000 dict" "$plist"
	/usr/libexec/PlistBuddy -c "Add :GlobalKeyMap:0x6f-0x100000:Action integer 25" "$plist"
	/usr/libexec/PlistBuddy -c "Add :GlobalKeyMap:0x6f-0x100000:Text string ''" "$plist"
	# Cmd+E (0x65) → Split Vertically with Current Profile (Action 26)
	/usr/libexec/PlistBuddy -c "Add :GlobalKeyMap:0x65-0x100000 dict" "$plist"
	/usr/libexec/PlistBuddy -c "Add :GlobalKeyMap:0x65-0x100000:Action integer 26" "$plist"
	/usr/libexec/PlistBuddy -c "Add :GlobalKeyMap:0x65-0x100000:Text string ''" "$plist"

	# Set the "Terminator Style" dynamic profile as the default profile
	defaults write com.googlecode.iterm2 "Default Bookmark Guid" -string "armada-profile"

	# Install Dynamic Profile (terminator-like appearance)
	local iterm2_profiles_dir="$HOME/Library/Application Support/iTerm2/DynamicProfiles"
	mkdir -p "$iterm2_profiles_dir"
	cp "$PROFILE_DIR/dotfiles/iterm2/terminator-style.json" "$iterm2_profiles_dir/terminator-style.json"

	# Case-insensitive tab completion
	if [ ! -f "$HOME/.inputrc" ] || ! grep -q 'completion-ignore-case' "$HOME/.inputrc" 2>/dev/null; then
		echo 'set completion-ignore-case On' >>"$HOME/.inputrc"
	fi
}

install_homebrew() {
	print_function_name
	if ! command -v brew >/dev/null 2>&1; then
		log "Installing Homebrew..."
		/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

		# Add Homebrew to PATH for Apple Silicon Macs
		if [[ $(uname -m) == 'arm64' ]]; then
			eval "$(/opt/homebrew/bin/brew shellenv)"
		fi
	fi

	# Re-evaluate brew shellenv to ensure PATH includes Homebrew for the
	# rest of this script (covers both fresh install and existing install)
	if [ "$(uname -m)" = "arm64" ]; then
		eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv 2>/dev/null || true)"
	else
		eval "$(/usr/local/bin/brew shellenv 2>/dev/null || /opt/homebrew/bin/brew shellenv 2>/dev/null || true)"
	fi

	# Set HOMEBREW_NO_AUTO_UPDATE to prevent brew from running git updates
	# during individual installs (we handle updates explicitly)
	export HOMEBREW_NO_AUTO_UPDATE=1

	# Ensure Homebrew's git uses the credential helper
	export HOMEBREW_NO_INSTALL_FROM_API=0
}

install_packages() {
	print_function_name

	# Remove stale/deprecated taps that cause git errors or auth prompts
	local stale_taps=("hashicorp/tap" "homebrew/cask-drivers" "homebrew/cask-versions" "homebrew/cask-fonts" "ubuntu/microk8s")
	for tap in "${stale_taps[@]}"; do
		if brew tap | grep -q "$tap"; then
			log "Removing stale tap: $tap"
			brew untap "$tap" 2>/dev/null || true
		fi
	done

	# Homebrew uses the API by default now; local taps waste space
	for tap in homebrew/core homebrew/cask; do
		if brew tap | grep -q "^${tap}$"; then
			log "Removing unnecessary tap: $tap"
			brew untap "$tap" 2>/dev/null || true
		fi
	done

	# Remove old/unwanted packages
	local unwanted=("python@3.8" "python@3.9" "pkg-config")
	for pkg in "${unwanted[@]}"; do
		if brew list "$pkg" &>/dev/null; then
			log "Removing unwanted package: $pkg"
			brew uninstall --ignore-dependencies "$pkg" 2>/dev/null || true
		fi
	done
	local unwanted_casks=("julia-app" "julia")
	local caskroom="$(brew --prefix)/Caskroom"
	for cask in "${unwanted_casks[@]}"; do
		if brew uninstall --cask --force "$cask" 2>/dev/null; then
			log "Removed unwanted cask: $cask"
		elif [ -d "$caskroom/$cask" ]; then
			log "Removing stale cask metadata: $cask"
			rm -rf "$caskroom/$cask"
		fi
	done

	log "Updating Homebrew..."
	# brew update can fail on stale taps — not critical
	brew update || log "Warning: brew update had errors, continuing..."
	log "Installing packages from Brewfile..."
	brew bundle --file="$PROFILE_DIR/tools/Brewfile"
	brew upgrade
	brew cleanup

	# Accept Xcode license (installed via mas in Brewfile)
	if command -v xcodebuild >/dev/null 2>&1; then
		sudo xcodebuild -license accept
	fi
}

setup_bash() {
	print_function_name
	# macOS ships with bash 3.2 (GPLv2). Homebrew installs bash 5+ which is
	# needed for associative arrays and other features used in .bash_aliases.
	local brew_bash="$(brew --prefix)/bin/bash"
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
		# Fix npm ownership if root-owned files exist
		for dir in "$HOME/.npm" "$HOME/.npm-global"; do
			if [ -d "$dir" ]; then
				sudo chown -R "$(id -u):$(id -g)" "$dir"
			fi
		done
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

setup_vscode() {
	print_function_name

	local vscode_app="/Applications/Visual Studio Code.app"

	# Install or reinstall if the .app is missing from /Applications
	# (handles stale Caskroom metadata where brew thinks it's installed but the app is gone)
	if [ ! -d "$vscode_app" ]; then
		log "VS Code not found in /Applications, installing..."
		brew reinstall --cask visual-studio-code
	fi

	# Add the `code` CLI to PATH
	local code_bin="$vscode_app/Contents/Resources/app/bin/code"
	if [ -f "$code_bin" ]; then
		ln -sf "$code_bin" /usr/local/bin/code
		log "VS Code CLI linked to /usr/local/bin/code"
	else
		log "VS Code binary not found after install, skipping configuration"
		return 1
	fi

	VSCODE_USER_DIR="$HOME/Library/Application Support/Code/User"
	configure_vscode
}

install_espanso() {
	print_function_name
	# Espanso is installed via Homebrew cask
	if command -v espanso >/dev/null 2>&1; then
		local espanso_config="$HOME/Library/Application Support/espanso"
		mkdir -p "$espanso_config/match"
		cp "$PROFILE_DIR/dotfiles/espanso_match_file.yml" "$espanso_config/match/base.yml"
		# Use Clipboard backend to avoid key injection issues (e.g. @ becoming ")
		sed -i '' 's/^# backend: Clipboard/backend: Clipboard/' "$espanso_config/config/default.yml"
		# Substitute placeholders with git config values
		local match_file="$espanso_config/match/base.yml"
		sed -i '' "s|__EMAIL__|$(git config --global user.email)|" "$match_file"
		sed -i '' "s|__GIT_USER__|$(git config --global user.name)|" "$match_file"
		sed -i '' "s|__PHONE__|$(git config --global user.phonenumber)|" "$match_file"
		espanso --version || true
	else
		log "espanso not found, skipping config"
	fi
}

install_tailscale() {
	print_function_name
	# Tailscale is installed via Homebrew cask. The cask installs the GUI app
	# but does not put the CLI on PATH. A symlink doesn't work because the
	# binary checks its bundle path, so we use a wrapper script instead.
	local tailscale_cli="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
	local wrapper_target="/usr/local/bin/tailscale"

	if [ -d "/Applications/Tailscale.app" ]; then
		log "Opening Tailscale.app (required to activate system extension)..."
		open -a Tailscale

		# Create CLI wrapper script (symlinks crash due to bundle identifier check)
		if [ -f "$tailscale_cli" ]; then
			log "Creating CLI wrapper: $wrapper_target"
			sudo rm -f "$wrapper_target"
			sudo tee "$wrapper_target" >/dev/null <<-WRAPPER
				#!/bin/bash
				exec "$tailscale_cli" "\$@"
			WRAPPER
			sudo chmod +x "$wrapper_target"
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

	# Gemini CLI is installed via Homebrew

	# Install/upgrade Claude Code
	if command -v claude >/dev/null 2>&1; then
		log "Claude Code already installed, upgrading..."
	else
		log "Installing Claude Code..."
	fi
	# Use arch -arm64 on Apple Silicon to ensure the native arm64 binary is
	# installed, even if the shell is running under Rosetta (which causes
	# uname -m to report x86_64 and triggers Bun AVX warnings)
	if [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = "1" ]; then
		curl -fsSL https://claude.ai/install.sh | arch -arm64 bash
	else
		curl -fsSL https://claude.ai/install.sh | bash
	fi

	# Install/upgrade ChatGPT CLI (shell-gpt)
	if command -v sgpt >/dev/null 2>&1; then
		log "shell-gpt already installed, upgrading..."
	else
		log "Installing ChatGPT CLI (shell-gpt)..."
	fi
	uv pip install -U shell-gpt

	log "AI CLI tools installation complete"
}

install_terraform() {
	print_function_name
	local arch
	if [ "$(uname -m)" = "arm64" ]; then
		arch="arm64"
	else
		arch="amd64"
	fi
	local latest_version
	latest_version=$(curl -s https://api.github.com/repos/hashicorp/terraform/releases/latest | grep -o '"tag_name":.*' | cut -d'v' -f2 | tr -d '",')
	curl -sLO "https://releases.hashicorp.com/terraform/$latest_version/terraform_${latest_version}_darwin_${arch}.zip"
	unzip "terraform_${latest_version}_darwin_${arch}.zip"
	sudo mv terraform /usr/local/bin/
	rm -rf terraform_* LICENSE.txt
	terraform version
}

install_webtools() {
	print_function_name
	# shfmt, shellcheck, and k9s are installed via Homebrew
	curl -sS https://webi.sh/awless | sh
}

main() {
	collect_user_input

	failed_functions=()

	run_function copy_dotfiles
	run_function set_git_config
	run_function install_homebrew
	run_function install_packages
	run_function setup_bash
	run_function install_pyenv
	run_function install_rust
	run_function install_node
	run_function install_go
	run_function setup_docker
	run_function setup_vscode
	run_function install_espanso
	run_function install_tailscale
	run_function install_terraform
	run_function install_starship
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
