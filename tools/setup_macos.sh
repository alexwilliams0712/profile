#!/bin/bash
echo "Setup running"

mkdir -p $HOME/CODE
export CODE_ROOT=$HOME/CODE
export PROJECT_ROOT=$HOME/profile
export PATH="/usr/local/bin:$PATH"
export PATH="/usr/local/sbin:$PATH"
export PATH="$HOME/.local/bin:$PATH"
export PROFILE_DIR=$(pwd)
export ARCHITECTURE=$(uname -m)
# Upstream installers should use the sudo ticket primed below and must not stop
# for their own confirmation prompts. Homebrew CLI ask mode is now the default;
# HOMEBREW_NO_ASK disables it, while NONINTERACTIVE covers its bootstrap script.
export NONINTERACTIVE=1
export HOMEBREW_NO_ASK=1
export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=10"
unset INTERACTIVE HOMEBREW_ASK
set -e
set -o pipefail

source "$PROFILE_DIR/tools/common.sh"
trap 'handle_error $LINENO' ERR

# Prompt for sudo once, then keep the timestamp warm for the whole install.
keep_sudo_alive

# Use the Homebrew matching the current architecture
brew_shellenv

install_command_line_tools() {
	print_function_name
	local clt_missing=false
	local clt_update_required=false
	local clt_placeholder="/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress"
	local clt_label=""
	local developer_dir=""
	local full_xcode_available=false

	developer_dir="$(xcode-select -p 2>/dev/null || true)"
	case "$developer_dir" in
	*.app/Contents/Developer)
		if /usr/bin/xcodebuild -version >/dev/null 2>&1 &&
			/usr/bin/xcrun --find clang >/dev/null 2>&1; then
			full_xcode_available=true
		fi
		;;
	esac

	if [ -z "$developer_dir" ]; then
		clt_missing=true
		clt_update_required=true
	elif ! /usr/sbin/pkgutil --pkg-info=com.apple.pkg.CLTools_Executables &>/dev/null; then
		# Prefer a current standalone CLT when softwareupdate offers one. A full
		# Xcode toolchain is still a valid fallback when it does not.
		log "Command Line Tools receipt is missing; checking for the current package..."
		clt_update_required=true
	elif command -v brew >/dev/null 2>&1; then
		local brew_doctor_output
		brew_doctor_output="$(brew doctor 2>&1 || true)"
		if printf '%s\n' "$brew_doctor_output" |
			grep -qiE 'newer Command Line Tools release is available|Command Line Tools are too outdated|outdated Command Line Tools'; then
			log "Command Line Tools are outdated; checking for the current package..."
			clt_update_required=true
		fi
	fi

	if [ "$clt_update_required" = true ]; then
		log "Searching for Xcode Command Line Tools..."
		# This marker makes softwareupdate include the standalone CLT package even
		# when Xcode or an older CLT is already selected.
		/usr/bin/sudo -n /usr/bin/touch "$clt_placeholder"
	fi

	clt_label=$(
		/usr/sbin/softwareupdate --list 2>&1 |
			grep -B 1 -E 'Command Line Tools' |
			awk -F'*' '/^ *\*/ {print $2}' |
			sed -e 's/^ *Label: //' -e 's/^ *//' |
			sort -V |
			tail -n 1
	) || true

	if [ "$clt_update_required" = true ]; then
		/usr/bin/sudo -n /bin/rm -f "$clt_placeholder"
	fi

	if [ -n "$clt_label" ]; then
		log "Installing $clt_label..."
		/usr/bin/sudo -n /usr/sbin/softwareupdate --install "$clt_label" --agree-to-license
	elif [ "$clt_update_required" = true ] && [ "$full_xcode_available" = true ]; then
		if [ -d /Library/Developer/CommandLineTools ]; then
			local stale_clt_backup
			stale_clt_backup="/Library/Developer/CommandLineTools.stale-$(date '+%Y%m%d%H%M%S')"
			log "Moving stale standalone Command Line Tools to $stale_clt_backup"
			/usr/bin/sudo -n /bin/mv /Library/Developer/CommandLineTools "$stale_clt_backup"
		fi
		log "softwareupdate did not offer standalone Command Line Tools; using the active full Xcode toolchain."
	elif [ "$clt_update_required" = true ]; then
		log "A current Command Line Tools package is required but softwareupdate did not offer one."
		return 1
	fi

	# Select the standalone CLT directory after a first-time headless install.
	if [ "$clt_missing" = true ] && [ -d /Library/Developer/CommandLineTools ]; then
		/usr/bin/sudo -n /usr/bin/xcode-select --switch /Library/Developer/CommandLineTools
	fi

	if ! xcode-select -p &>/dev/null; then
		log "Xcode Command Line Tools were not available from softwareupdate."
		return 1
	fi
}

copy_dotfiles() {
	print_function_name
	mkdir -p "$HOME/.config"
	cp "$PROFILE_DIR/dotfiles/starship.toml" "$HOME/.config/starship.toml"
	cp "$PROFILE_DIR/dotfiles/.profile" "$HOME/.profile"
	cp "$PROFILE_DIR/VERSION" "$HOME/BASH_PROFILE_VERSION"
	cp "$PROFILE_DIR/dotfiles/.bashrc" "$HOME/.bashrc"
	cp "$PROFILE_DIR/dotfiles/.prettierrc" "$HOME/.prettierrc"
	cp "$PROFILE_DIR/dotfiles/.bash_aliases" "$HOME/.bash_aliases"

	# Helper scripts that .bash_aliases shells out to (keeps the sourced
	# .bash_aliases small/fast). Same path is used on macOS and Linux.
	mkdir -p "$HOME/.local/bin"
	cp "$PROFILE_DIR/dotfiles/bin/json_formatter.py" "$HOME/.local/bin/json_formatter.py"
	chmod +x "$HOME/.local/bin/json_formatter.py"
	cp "$PROFILE_DIR/dotfiles/bin/work-proxy" "$HOME/.local/bin/work-proxy"
	chmod +x "$HOME/.local/bin/work-proxy"

	copy_btop_config

	# Ghostty config (shared between macOS and Linux)
	mkdir -p "$HOME/.config/ghostty"
	cp "$PROFILE_DIR/dotfiles/ghostty/config" "$HOME/.config/ghostty/config"

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
		NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

		# Add Homebrew to PATH for Apple Silicon Macs
		if [[ $(uname -m) == 'arm64' ]]; then
			eval "$(/opt/homebrew/bin/brew shellenv)"
		fi
	fi

	# Re-evaluate brew shellenv to ensure PATH includes Homebrew for the
	# rest of this script (covers both fresh install and existing install)
	brew_shellenv

	# Set HOMEBREW_NO_AUTO_UPDATE to prevent brew from running git updates
	# during individual installs (we handle updates explicitly)
	export HOMEBREW_NO_AUTO_UPDATE=1

	# Ensure Homebrew's git uses the credential helper
	export HOMEBREW_NO_INSTALL_FROM_API=0
}

cask_app_artifact_paths() {
	local cask="$1"
	local applications_dir="${APPLICATIONS_DIR:-/Applications}"
	local artifact
	local artifact_path

	while IFS= read -r artifact; do
		artifact="${artifact% (App)}"
		case "$artifact" in
		*" -> "*) artifact="${artifact##* -> }" ;;
		esac
		case "$artifact" in
		/*) artifact_path="$artifact" ;;
		*) artifact_path="$applications_dir/${artifact##*/}" ;;
		esac
		printf '%s\n' "$artifact_path"
	done < <(
		brew info --cask "$cask" 2>/dev/null |
			awk '
				/^==> Artifacts$/ { in_artifacts = 1; next }
				/^==>/ { in_artifacts = 0 }
				in_artifacts && / \(App\)$/ { print }
			'
	)
}

cask_has_existing_app_artifact() {
	local cask="$1"
	local artifact_path

	while IFS= read -r artifact_path; do
		if [ -e "$artifact_path" ]; then
			return 0
		fi
	done < <(cask_app_artifact_paths "$cask")

	return 1
}

cask_has_missing_app_artifact() {
	local cask="$1"
	local artifact_path

	while IFS= read -r artifact_path; do
		if [ ! -e "$artifact_path" ]; then
			return 0
		fi
	done < <(cask_app_artifact_paths "$cask")

	return 1
}

install_packages() {
	print_function_name

	# Remove stale/deprecated taps that cause git errors or auth prompts
	local stale_taps=("hashicorp/tap" "homebrew/cask-drivers" "homebrew/cask-versions" "homebrew/cask-fonts" "jenkins-x/jx" "ubuntu/microk8s")
	for tap in "${stale_taps[@]}"; do
		if brew tap | grep -q "$tap"; then
			log "Removing stale tap: $tap"
			brew untap "$tap" 2>/dev/null || true
		fi
	done

	# Homebrew uses the API by default now; local taps waste space and, worse,
	# their stale cask .rb sources shadow the live API casks. A leftover
	# definition referencing the long-removed `appcast` stanza (removed in
	# brew 4.3) makes a cask "unreadable" and aborts the whole `brew bundle`.
	# Force-untap and delete the leftover tap checkouts so the API casks win.
	local brew_repo
	brew_repo="$(brew --repository)"
	for tap in homebrew/core homebrew/cask; do
		if brew tap | grep -q "^${tap}$"; then
			log "Removing unnecessary tap: $tap"
			brew untap --force "$tap" 2>/dev/null || true
		fi
		# Remove any leftover on-disk tap checkout even if `brew tap` no longer
		# lists it (untap can leave the directory behind).
		local tap_dir="$brew_repo/Library/Taps/${tap%/*}/homebrew-${tap#*/}"
		if [ -d "$tap_dir" ]; then
			log "Removing leftover tap directory: $tap_dir"
			rm -rf "$tap_dir"
		fi
	done

	# Remove old/unwanted packages
	local unwanted=("python@3.8" "python@3.9" "pkg-config" "speedtest-cli")
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

	# Installed `.metadata` under Caskroom is Homebrew's receipt and must remain
	# intact. Only drop disposable downloaded cask metadata from the cache.
	# Guard the path so an empty `brew --cache` can never expand to `/Cask`.
	local brew_cache
	brew_cache="$(brew --cache 2>/dev/null)"
	[ -n "$brew_cache" ] && rm -rf "${brew_cache:?}/Cask" 2>/dev/null || true

	log "Updating Homebrew..."
	# Reset local repo state so the JSON API (not stale local taps) is the
	# source of truth, then update. Both are best-effort — non-fatal on error.
	brew update-reset || log "Warning: brew update-reset had errors, continuing..."
	brew update || log "Warning: brew update had errors, continuing..."
	log "Installing packages from Brewfile..."
	# Homebrew 6 can misclassify casks as formulae when Bundle prefetches a mixed
	# batch. Isolate each package type so one failed group cannot block the rest.
	local brewfile="$PROFILE_DIR/tools/Brewfile"
	local formulae casks mas_apps taps
	formulae="$(brew bundle list --file="$brewfile" --formula | tr '\n' ' ')"
	casks="$(brew bundle list --file="$brewfile" --cask | tr '\n' ' ')"
	mas_apps="$(brew bundle list --file="$brewfile" --mas | tr '\n' ' ')"
	taps="$(brew bundle list --file="$brewfile" --tap | tr '\n' ' ')"
	local bundle_failed=0
	local cask

	# Repair incomplete installations that Homebrew's receipt-only checks miss.
	for cask in $casks; do
		if brew list --versions --cask "$cask" &>/dev/null; then
			if ! cask_has_missing_app_artifact "$cask"; then
				continue
			fi
			log "Reinstalling cask with missing application artifact: $cask"
			if ! brew reinstall --cask --force "$cask"; then
				log "Warning: Could not restore application artifact for $cask; continuing..."
				bundle_failed=1
			fi
			continue
		fi
		if [ -d "$caskroom/$cask" ]; then
			log "Repairing invalid Homebrew metadata for $cask..."
			if ! brew reinstall --cask --force "$cask"; then
				log "Warning: Could not repair Homebrew metadata for $cask; continuing..."
				bundle_failed=1
			fi
		elif cask_has_existing_app_artifact "$cask"; then
			log "Reinstalling unmanaged application cask: $cask"
			if ! brew install --cask --force "$cask"; then
				log "Warning: Could not reinstall unmanaged cask $cask; continuing..."
				bundle_failed=1
			fi
		fi
	done

	if ! HOMEBREW_BUNDLE_CASK_SKIP="$casks" HOMEBREW_BUNDLE_MAS_SKIP="$mas_apps" \
		brew bundle --file="$brewfile"; then
		log "Warning: Homebrew formula installation reported errors; continuing..."
		bundle_failed=1
	fi
	if ! HOMEBREW_BUNDLE_BREW_SKIP="$formulae" HOMEBREW_BUNDLE_MAS_SKIP="$mas_apps" \
		HOMEBREW_BUNDLE_TAP_SKIP="$taps" brew bundle --file="$brewfile"; then
		log "Warning: Homebrew cask installation reported errors; continuing..."
		bundle_failed=1
	fi
	if ! HOMEBREW_BUNDLE_BREW_SKIP="$formulae" HOMEBREW_BUNDLE_CASK_SKIP="$casks" \
		HOMEBREW_BUNDLE_TAP_SKIP="$taps" brew bundle --file="$brewfile"; then
		log "Warning: Mac App Store installation reported errors; continuing..."
		bundle_failed=1
	fi
	# brew bundle installs and upgrades Brewfile entries by default. Do not run
	# a global greedy upgrade here: it also touches unrelated legacy casks and
	# can fail the profile setup because of packages outside this Brewfile.
	brew cleanup

	# Accept the Xcode license only when the current installation requires it.
	if command -v xcodebuild >/dev/null 2>&1 && ! xcodebuild -license check >/dev/null 2>&1; then
		run_sudo xcodebuild -license accept
	fi

	return "$bundle_failed"
}

setup_bash() {
	print_function_name
	# macOS ships with bash 3.2 (GPLv2). Homebrew installs bash 5+ which is
	# needed for associative arrays and other features used in .bash_aliases.
	local brew_bash="$(brew --prefix)/bin/bash"
	if [ -f "$brew_bash" ]; then
		if ! grep -q "$brew_bash" /etc/shells 2>/dev/null; then
			log "Adding Homebrew bash to /etc/shells"
			echo "$brew_bash" | run_sudo tee -a /etc/shells
		fi
		if [ "$SHELL" != "$brew_bash" ]; then
			log "Setting Homebrew bash as default shell"
			run_sudo chsh -s "$brew_bash" "$USER"
		fi
	fi

	# macOS Terminal/iTerm2 open login shells which source .bash_profile,
	# not .bashrc. Ensure .bash_profile sources .bashrc.
	if [ ! -f "$HOME/.bash_profile" ] || ! grep -q '.bashrc' "$HOME/.bash_profile" 2>/dev/null; then
		log "Configuring .bash_profile to source .bashrc"
		echo '[ -f ~/.bashrc ] && source ~/.bashrc' >>"$HOME/.bash_profile"
	fi
}

install_ruby() {
	print_function_name
	# Ruby is installed via Homebrew. Use Homebrew's Ruby instead of macOS system Ruby
	# so we get a current version and can install gems without sudo.
	local brew_ruby="/opt/homebrew/opt/ruby/bin/ruby"
	if [ -f "$brew_ruby" ]; then
		export PATH="/opt/homebrew/opt/ruby/bin:/opt/homebrew/lib/ruby/gems/4.0.0/bin:$PATH"
		log "Using Homebrew Ruby: $("$brew_ruby" --version)"

		# Install bundler (used for managing project-level gem dependencies like fastlane)
		if ! command -v bundle >/dev/null 2>&1; then
			log "Installing Bundler..."
			gem install bundler
		else
			log "Bundler already installed: $(bundle --version)"
		fi
	else
		log "Homebrew Ruby not found, skipping Ruby setup"
	fi
}

install_node() {
	print_function_name
	# Node is installed via Homebrew
	if command -v node >/dev/null 2>&1; then
		node -v
		npm -v
		# Fix npm ownership if root-owned files exist
		for dir in "$HOME/.npm" "$HOME/.npm-global"; do
			if [ -d "$dir" ] &&
				[ -n "$(find "$dir" ! -user "$(id -un)" -print -quit 2>/dev/null)" ]; then
				log "Fixing ownership under $dir"
				run_sudo chown -R "$(id -u):$(id -g)" "$dir"
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

	# Docker Desktop is installed by the Brewfile but started only by the user.
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
		local config_file="$espanso_config/config/default.yml"
		mkdir -p "$espanso_config/config" "$espanso_config/match"
		cp "$PROFILE_DIR/dotfiles/espanso_match_file.yml" "$espanso_config/match/base.yml"
		# Use Clipboard backend to avoid key injection issues (e.g. @ becoming ")
		if [ ! -f "$config_file" ]; then
			printf 'backend: Clipboard\n' >"$config_file"
		elif grep -qE '^[[:space:]]*#?[[:space:]]*backend:' "$config_file"; then
			sed -i '' -E 's/^[[:space:]]*#?[[:space:]]*backend:.*/backend: Clipboard/' "$config_file"
		else
			printf '\nbackend: Clipboard\n' >>"$config_file"
		fi
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
	if [ ! -d /usr/local/bin ] || [ ! -w /usr/local/bin ]; then
		mkdir -p "$HOME/.local/bin"
		wrapper_target="$HOME/.local/bin/tailscale"
	fi

	if [ -d "/Applications/Tailscale.app" ]; then
		log "Opening Tailscale.app (required to activate system extension)..."
		open -a Tailscale

		# Create CLI wrapper script (symlinks crash due to bundle identifier check)
		if [ -f "$tailscale_cli" ]; then
			if [ -x "$wrapper_target" ] &&
				grep -Fq "exec \"$tailscale_cli\"" "$wrapper_target"; then
				log "Tailscale CLI wrapper is already current: $wrapper_target"
			else
				log "Creating CLI wrapper: $wrapper_target"
				rm -f "$wrapper_target"
				printf '#!/bin/bash\nexec "%s" "$@"\n' "$tailscale_cli" >"$wrapper_target"
				chmod +x "$wrapper_target"
			fi
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
	if command -v terraform >/dev/null 2>&1 &&
		terraform version | head -n 1 | grep -qx "Terraform v$latest_version"; then
		log "Terraform $latest_version is already installed."
		terraform version
		return 0
	fi

	local tmp_dir
	tmp_dir="$(mktemp -d)"
	curl -fsSL "https://releases.hashicorp.com/terraform/$latest_version/terraform_${latest_version}_darwin_${arch}.zip" \
		-o "$tmp_dir/terraform.zip" || {
		rm -rf "$tmp_dir"
		return 1
	}
	unzip -oq "$tmp_dir/terraform.zip" -d "$tmp_dir" || {
		rm -rf "$tmp_dir"
		return 1
	}
	local install_dir="/usr/local/bin"
	if [ ! -d "$install_dir" ] || [ ! -w "$install_dir" ]; then
		install_dir="$HOME/.local/bin"
		mkdir -p "$install_dir"
	fi
	install -m 0755 "$tmp_dir/terraform" "$install_dir/terraform" || {
		rm -rf "$tmp_dir"
		return 1
	}
	rm -rf "$tmp_dir"
	terraform version
}

install_webtools() {
	print_function_name
	# shfmt, shellcheck, and k9s are installed via Homebrew
	curl -sS https://webi.sh/awless | sh
}

install_syncthing() {
	print_function_name
	# Syncthing is installed as a formula via the Brewfile (brew "syncthing").
	# It ships a launchd agent; start it so it runs at login and keeps folders
	# (e.g. ~/dotfiles) in sync in the background. Idempotent — a second start
	# just re-registers the already-running service.
	if command -v syncthing >/dev/null 2>&1; then
		brew services start syncthing || log "Could not start syncthing service"
		syncthing --version | head -1
	else
		log "syncthing not found (brew bundle may have failed); skipping service start"
	fi
}

main() {
	# A fresh mac needs CLT before git can read the existing identity. On a
	# configured mac, collect the two optional values first, then check updates.
	local clt_was_missing=false
	local preflight_steps=(install_command_line_tools)
	local before_brew_steps=(
		copy_dotfiles
		set_git_config
		install_homebrew
	)
	local after_brew_steps=(
		install_packages
		setup_bash
		install_ruby
		install_pyenv
		install_rust
		install_foundry
		install_node
		install_go
		setup_docker
		setup_vscode
		install_espanso
		install_tailscale
		install_terraform
		install_starship
		install_webtools
		install_syncthing
		install_ai
	)
	failed_functions=()
	setup_progress_start "${preflight_steps[@]}" "${before_brew_steps[@]}" "${after_brew_steps[@]}"
	if ! xcode-select -p &>/dev/null; then
		clt_was_missing=true
		run_functions "${preflight_steps[@]}"
		# Git cannot read the existing identity until this required preflight succeeds.
		if [ ${#failed_functions[@]} -ne 0 ]; then
			return 1
		fi
	fi

	collect_user_input

	if [ "$clt_was_missing" = false ]; then
		before_brew_steps=("${preflight_steps[@]}" "${before_brew_steps[@]}")
	fi
	run_functions "${before_brew_steps[@]}"
	# run_function isolates each step so errors are reliable. Refresh the
	# environment changes made by install_homebrew in the parent shell.
	brew_shellenv
	export HOMEBREW_NO_AUTO_UPDATE=1
	export HOMEBREW_NO_INSTALL_FROM_API=0
	run_functions "${after_brew_steps[@]}"

	# Report failures if any
	if [ ${#failed_functions[@]} -ne 0 ]; then
		echo -e "\n\033[1;91mThe following functions failed:\033[0m"
		printf '\033[1;91m%s\033[0m\n' "${failed_functions[@]}"
		echo -e "\n\033[1;91mPlease check the above functions and try running them individually.\033[0m"
	fi

	exit_script
}
main
