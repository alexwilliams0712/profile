#!/bin/bash
echo "Setup running"

mkdir -p "$HOME/CODE"
export PATH="$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:$PATH"
PROFILE_DIR="$(pwd)"
export PROFILE_DIR
# Upstream installers must not stop for their own confirmation prompts.
# Homebrew may still request administrator approval after it deliberately
# invalidates sudo. HOMEBREW_NO_ASK disables its CLI ask mode, while
# NONINTERACTIVE covers its bootstrap script.
export NONINTERACTIVE=1
export HOMEBREW_NO_ASK=1
export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=10"
unset INTERACTIVE HOMEBREW_ASK HOMEBREW_NO_INSTALL_FROM_API
set -e
set -o pipefail

source "$PROFILE_DIR/tools/common.sh"
# shellcheck disable=SC1091
source "$PROFILE_DIR/tools/macos_helpers.sh"
trap 'handle_error $LINENO' ERR

# Use the Homebrew matching the current architecture. Privileged steps request
# approval only when needed because Homebrew invalidates cached sudo tickets.
brew_shellenv

install_command_line_tools() {
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
	elif command_line_tools_update_required "$full_xcode_available"; then
		if ! clt_receipt_exists; then
			# Prefer a current standalone CLT when softwareupdate offers one. A full
			# Xcode toolchain is still a valid fallback when it does not.
			log "Command Line Tools receipt is missing; checking for the current package..."
		else
			log "Command Line Tools are outdated; checking for the current package..."
		fi
		clt_update_required=true
	fi

	# A valid full Xcode is preferable to reinstalling optional standalone tools.
	# Validate that Homebrew accepts it, then remove only the stale CLT directory.
	if [ "$clt_update_required" = true ] && [ "$full_xcode_available" = true ] &&
		use_full_xcode_for_invalid_command_line_tools "$full_xcode_available"; then
		clt_update_required=false
	fi

	if [ "$clt_update_required" = true ]; then
		log "Searching for Xcode Command Line Tools..."
		# This marker makes softwareupdate include the standalone CLT package even
		# when Xcode or an older CLT is already selected.
		run_sudo /usr/bin/touch "$clt_placeholder"
		clt_label="$(available_command_line_tools_label)" || true
		run_sudo /bin/rm -f "$clt_placeholder"

		if [ -n "$clt_label" ]; then
			log "Installing $clt_label..."
			if ! run_sudo /usr/sbin/softwareupdate --install "$clt_label" --agree-to-license; then
				log "softwareupdate did not install $clt_label; validating the active toolchain."
			fi
		fi
	fi

	if [ "$clt_update_required" = true ] &&
		! use_full_xcode_for_invalid_command_line_tools "$full_xcode_available"; then
		log "A current Command Line Tools package is required but softwareupdate did not install one."
		return 1
	fi

	# Select the standalone CLT directory after a first-time headless install.
	if [ "$clt_missing" = true ] && [ -d /Library/Developer/CommandLineTools ]; then
		run_sudo /usr/bin/xcode-select --switch /Library/Developer/CommandLineTools
	fi

	if ! xcode-select -p &>/dev/null; then
		log "Xcode Command Line Tools were not available from softwareupdate."
		return 1
	fi
}

copy_dotfiles() {
	copy_shared_dotfiles

	# Ghostty loads this macOS-specific location after its XDG config.
	local ghostty_config_dir="$HOME/Library/Application Support/com.mitchellh.ghostty"
	mkdir -p "$ghostty_config_dir"
	cp "$PROFILE_DIR/dotfiles/ghostty/config" "$ghostty_config_dir/config.ghostty"
	# Do not load the legacy file previously managed by this profile as well.
	rm -f "$HOME/.config/ghostty/config"

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

}

install_homebrew() {
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
	# Remove stale/deprecated taps that cause git errors or auth prompts
	local stale_taps=("hashicorp/tap" "homebrew/cask-drivers" "homebrew/cask-versions" "homebrew/cask-fonts" "jenkins-x/jx" "ubuntu/microk8s")
	local installed_taps
	installed_taps="$(brew tap 2>/dev/null || true)"
	for tap in "${stale_taps[@]}"; do
		if printf '%s\n' "$installed_taps" | grep -Fxq "$tap"; then
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
		if printf '%s\n' "$installed_taps" | grep -Fxq "$tap"; then
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
	local unwanted=("python@3.8" "python@3.9" "pkgconf" "speedtest-cli")
	local installed_formulae
	installed_formulae="$(brew list --formula 2>/dev/null || true)"
	for pkg in "${unwanted[@]}"; do
		if printf '%s\n' "$installed_formulae" | grep -Fxq "$pkg"; then
			log "Removing unwanted package: $pkg"
			brew uninstall --ignore-dependencies "$pkg" 2>/dev/null || true
		fi
	done
	local caskroom
	caskroom="$(brew --prefix)/Caskroom"

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
	local installed_auto_update_casks=""

	log "Homebrew may request administrator approval for privileged cask installers."
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
	# shellcheck disable=SC2086 # Split the Brewfile cask list into arguments.
	installed_auto_update_casks="$(casks_managed_by_own_updater $casks)"

	if ! HOMEBREW_BUNDLE_CASK_SKIP="$casks" HOMEBREW_BUNDLE_MAS_SKIP="$mas_apps" \
		brew bundle --file="$brewfile"; then
		log "Warning: Homebrew formula installation reported errors; continuing..."
		bundle_failed=1
	fi
	if ! HOMEBREW_BUNDLE_BREW_SKIP="$formulae" HOMEBREW_BUNDLE_MAS_SKIP="$mas_apps" \
		HOMEBREW_BUNDLE_TAP_SKIP="$taps" HOMEBREW_BUNDLE_CASK_SKIP="$installed_auto_update_casks" \
		brew bundle --file="$brewfile"; then
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

install_go() {
	# Go is installed via Homebrew
	if command -v go >/dev/null 2>&1; then
		go version
		go install github.com/dim13/otpauth@latest
	else
		log "Go not found, skipping go installs"
	fi
}

setup_docker() {
	log "Setting up Docker..."
	mkdir -p ~/.docker/cli-plugins

	# Symlink docker-compose from Homebrew if available
	if [ -f /opt/homebrew/opt/docker-compose/bin/docker-compose ]; then
		ln -sfn /opt/homebrew/opt/docker-compose/bin/docker-compose ~/.docker/cli-plugins/docker-compose
	fi

	# Docker Desktop is installed by the Brewfile but started only by the user.
}

setup_vscode() {
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
	# shfmt, shellcheck, and k9s are installed via Homebrew
	curl -sS https://webi.sh/awless | sh
}

install_syncthing() {
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
		install_webtools
		install_syncthing
		install_ai
	)
	failed_functions=()
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
