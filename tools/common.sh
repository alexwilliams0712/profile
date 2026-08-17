#!/bin/bash
# Shared functions used by both setup_macos.sh and setup_ubuntu.sh

export DEFAULT_PYTHON_VERSION="3.14.5"

handle_error() {
	echo "An error occurred on line $1"
}

# Prime the sudo timestamp once, then keep it warm in the background on Linux.
# Homebrew deliberately resets the timestamp, so macOS uses foreground
# run_sudo calls that can re-prompt when necessary.
# - Idempotent: a second call is a no-op while a loop is already running.
# - set -e / pipefail safe: the priming `sudo -v` is guarded with `|| return`,
#   and the background loop's commands can't abort the parent shell.
# - The loop exits on its own once the parent script ($$) is gone, is killed by
#   the EXIT trap on error/early-exit paths, and is killed explicitly by
#   exit_script before it returns or replaces the setup process.
SUDO_KEEPALIVE_PID=""
sudo_command() {
	/usr/bin/sudo "$@"
}

keep_sudo_alive() {
	local parent_pid=$$

	# Already running? Do nothing.
	if [ -n "$SUDO_KEEPALIVE_PID" ] && kill -0 "$SUDO_KEEPALIVE_PID" 2>/dev/null; then
		return 0
	fi
	# Prompt for the password once (non-fatal under set -e if the user aborts).
	sudo_command -v || return 1
	# Explicitly extend the cached credentials until this script exits. Running
	# an arbitrary sudo command does not reliably refresh the timestamp on macOS.
	(
		local sleep_pid=""
		trap '[ -n "$sleep_pid" ] && kill "$sleep_pid" 2>/dev/null || true; exit 0' HUP INT TERM
		while true; do
			sudo_command -n -v 2>/dev/null || true
			sleep 30 &
			sleep_pid=$!
			wait "$sleep_pid" 2>/dev/null || exit 0
			sleep_pid=""
			kill -0 "$parent_pid" 2>/dev/null || exit 0
		done
	) </dev/null >/dev/null 2>&1 9>&- &
	SUDO_KEEPALIVE_PID=$!
	# Reap the loop when the script exits (without clobbering the ERR trap).
	trap 'setup_progress_restore_terminal; stop_sudo_keepalive' EXIT
}

stop_sudo_keepalive() {
	if [ -z "$SUDO_KEEPALIVE_PID" ]; then
		return
	fi
	kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
	wait "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
	SUDO_KEEPALIVE_PID=""
}

run_sudo() {
	if sudo_command -n -v 2>/dev/null; then
		sudo_command -n "$@"
	else
		log "Administrator approval is required to continue."
		sudo_command "$@"
	fi
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

SETUP_PROGRESS_CURRENT=0
SETUP_PROGRESS_TOTAL=0
SETUP_PROGRESS_FAILED=0
SETUP_PROGRESS_PINNED=0
SETUP_PROGRESS_ROWS=0
SETUP_PROGRESS_COLUMNS=0
SETUP_PROGRESS_LABEL=""
SETUP_PROGRESS_STATE="RUN"
SETUP_PROGRESS_LINE=""
SETUP_PROGRESS_DEFER_FINISH=0
SETUP_PROGRESS_CSR_PIN=""
SETUP_PROGRESS_CSR_FULL=""
SETUP_PROGRESS_CUP_OUTPUT=""
SETUP_PROGRESS_CUP_FOOTER=""
SETUP_PROGRESS_EL=""
SETUP_PROGRESS_SC=""
SETUP_PROGRESS_RC=""

setup_progress_start() {
	SETUP_PROGRESS_CURRENT=0
	SETUP_PROGRESS_TOTAL="$#"
	SETUP_PROGRESS_FAILED=0
	SETUP_PROGRESS_PINNED=0
	SETUP_PROGRESS_LABEL=""
	SETUP_PROGRESS_STATE="RUN"
	SETUP_PROGRESS_LINE=""
	SETUP_PROGRESS_DEFER_FINISH=0
}

setup_progress_has_terminal() {
	if [ "${PROFILE_SETUP_OUTPUT_TTY:-}" = 1 ] &&
		[ "${PROFILE_SETUP_PROGRESS_FD:-}" = 9 ] &&
		(: >&9) 2>/dev/null; then
		return 0
	fi
	[ -z "${PROFILE_SETUP_OUTPUT_TTY:-}" ] && [ -t 1 ]
}

setup_progress_write() {
	if [ "${PROFILE_SETUP_PROGRESS_FD:-}" = 9 ]; then
		printf '%s' "$1" >&9 2>/dev/null || true
		return
	fi
	printf '%s' "$1" || true
}

setup_progress_read_dimensions() {
	local size=""
	local rows=""
	local columns=""

	if [ "${PROFILE_SETUP_PROGRESS_FD:-}" = 9 ]; then
		size="$(stty size <&9 2>/dev/null || true)"
	else
		size="$(stty size 2>/dev/null || true)"
	fi
	rows="${size%% *}"
	columns="${size##* }"
	case "$rows" in
	'' | *[!0-9]* | 0) rows="${LINES:-24}" ;;
	esac
	case "$columns" in
	'' | *[!0-9]* | 0) columns="${COLUMNS:-80}" ;;
	esac
	case "$rows" in
	'' | *[!0-9]*) rows=24 ;;
	esac
	case "$columns" in
	'' | *[!0-9]*) columns=80 ;;
	esac
	SETUP_PROGRESS_ROWS="$rows"
	SETUP_PROGRESS_COLUMNS="$columns"
	if [ "$rows" -lt 3 ] || [ "$columns" -lt 12 ]; then
		return 1
	fi
}

setup_progress_read_capabilities() {
	SETUP_PROGRESS_CSR_PIN="$(tput csr 0 "$((SETUP_PROGRESS_ROWS - 2))" 2>/dev/null)" || return 1
	SETUP_PROGRESS_CSR_FULL="$(tput csr 0 "$((SETUP_PROGRESS_ROWS - 1))" 2>/dev/null)" || return 1
	SETUP_PROGRESS_CUP_OUTPUT="$(tput cup "$((SETUP_PROGRESS_ROWS - 2))" 0 2>/dev/null)" || return 1
	SETUP_PROGRESS_CUP_FOOTER="$(tput cup "$((SETUP_PROGRESS_ROWS - 1))" 0 2>/dev/null)" || return 1
	SETUP_PROGRESS_EL="$(tput el 2>/dev/null)" || return 1
	SETUP_PROGRESS_SC="$(tput sc 2>/dev/null)" || return 1
	SETUP_PROGRESS_RC="$(tput rc 2>/dev/null)" || return 1
}

setup_progress_pin() {
	local sequence

	if [ "$SETUP_PROGRESS_PINNED" -eq 1 ]; then
		return 0
	fi
	setup_progress_has_terminal || return 1
	setup_progress_read_dimensions || return 1
	[ "${TERM:-dumb}" != dumb ] || return 1
	setup_progress_read_capabilities || return 1
	sequence="${SETUP_PROGRESS_CSR_PIN}${SETUP_PROGRESS_CUP_OUTPUT}${SETUP_PROGRESS_EL}"
	setup_progress_write "$sequence"
	SETUP_PROGRESS_PINNED=1
	trap 'setup_progress_handle_resize' WINCH
}

setup_progress_restore_terminal() {
	local sequence

	if [ "$SETUP_PROGRESS_PINNED" -ne 1 ]; then
		return
	fi
	if [ -n "${PROFILE_SETUP_PROGRESS_STATE_FILE:-}" ] &&
		[ "$SETUP_PROGRESS_DEFER_FINISH" -eq 1 ] && [ "${1:-}" != force ]; then
		return
	fi
	sequence="${SETUP_PROGRESS_SC}${SETUP_PROGRESS_CUP_FOOTER}${SETUP_PROGRESS_EL}${SETUP_PROGRESS_CSR_FULL}${SETUP_PROGRESS_RC}"
	setup_progress_write "$sequence"
	SETUP_PROGRESS_PINNED=0
	setup_progress_clear_recorded_state
}

setup_progress_finish() {
	local sequence

	if [ "$SETUP_PROGRESS_PINNED" -eq 1 ]; then
		if [ -n "${PROFILE_SETUP_PROGRESS_STATE_FILE:-}" ]; then
			SETUP_PROGRESS_DEFER_FINISH=1
			return
		fi
		sequence="${SETUP_PROGRESS_CSR_FULL}${SETUP_PROGRESS_CUP_FOOTER}${SETUP_PROGRESS_EL}${SETUP_PROGRESS_LINE}"$'\n'
		setup_progress_write "$sequence"
		SETUP_PROGRESS_PINNED=0
	fi
	trap - WINCH
}

setup_progress_handle_resize() {
	local label="$SETUP_PROGRESS_LABEL"
	local state="$SETUP_PROGRESS_STATE"
	local old_cup_footer="$SETUP_PROGRESS_CUP_FOOTER"
	local sequence

	if ! setup_progress_read_dimensions || ! setup_progress_read_capabilities; then
		sequence=$'\033[r'"${old_cup_footer}${SETUP_PROGRESS_EL}"
		setup_progress_write "$sequence"
		SETUP_PROGRESS_PINNED=0
		setup_progress_clear_recorded_state
		trap - WINCH
		return
	fi
	sequence="${SETUP_PROGRESS_CSR_FULL}${old_cup_footer}${SETUP_PROGRESS_EL}${SETUP_PROGRESS_CUP_FOOTER}${SETUP_PROGRESS_EL}${SETUP_PROGRESS_CSR_PIN}${SETUP_PROGRESS_CUP_OUTPUT}"
	setup_progress_write "$sequence"
	setup_progress_render "$label" "$state"
}

setup_progress_clear_recorded_state() {
	if [ -z "${PROFILE_SETUP_PROGRESS_STATE_FILE:-}" ]; then
		return
	fi
	if ! : >|"$PROFILE_SETUP_PROGRESS_STATE_FILE" 2>/dev/null; then
		PROFILE_SETUP_PROGRESS_STATE_FILE=""
	fi
}

setup_progress_record_state() {
	local summary_state="OK"
	local summary

	if [ -z "${PROFILE_SETUP_PROGRESS_STATE_FILE:-}" ]; then
		return
	fi
	if [ "$SETUP_PROGRESS_STATE" = RUN ] && [ "$SETUP_PROGRESS_FAILED" -eq 0 ]; then
		summary_state="RUN"
	elif [ "$SETUP_PROGRESS_FAILED" -ne 0 ]; then
		summary_state="FAIL"
	fi
	summary="$SETUP_PROGRESS_CURRENT/$SETUP_PROGRESS_TOTAL $summary_state $SETUP_PROGRESS_LABEL"
	if ! {
		printf '%s\n' "$SETUP_PROGRESS_ROWS"
		printf '%s\n' "$SETUP_PROGRESS_COLUMNS"
		printf '%s\n' "$SETUP_PROGRESS_LINE"
		printf '%s\n' "$summary"
	} 2>/dev/null >|"$PROFILE_SETUP_PROGRESS_STATE_FILE"; then
		PROFILE_SETUP_PROGRESS_STATE_FILE=""
	fi
}

run_functions() {
	local func_name

	for func_name in "$@"; do
		run_function "$func_name"
	done
}

setup_progress_build_line() {
	local label="$1"
	local state="$2"
	local width=28
	local filled
	local remaining
	local percent
	local ix
	local completed_bar=""
	local remaining_bar=""
	local head=""
	local symbol="RUN"
	local bar_colour=""
	local remaining_colour=""
	local status_colour=""
	local colour_reset=""
	local locale="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"
	local completed_char="="
	local remaining_char="-"
	local head_char=">"
	local unicode_output=0
	local live_output="$SETUP_PROGRESS_PINNED"
	local live_label="$label"
	local compact_output=0
	local display_status
	local count
	local fixed_width
	local available_width
	local terminal_columns
	local progress_line

	percent=$((SETUP_PROGRESS_CURRENT * 100 / SETUP_PROGRESS_TOTAL))
	count="${SETUP_PROGRESS_CURRENT}/${SETUP_PROGRESS_TOTAL}"
	case "$locale" in
	*[Uu][Tt][Ff]-8* | *[Uu][Tt][Ff]8*)
		if [ "$live_output" -eq 1 ]; then
			unicode_output=1
			completed_char="━"
			remaining_char="━"
			head_char="╺"
		fi
		;;
	esac
	display_status="$SETUP_PROGRESS_FAILED"
	if [ "$state" = RUN ] && [ "$display_status" -eq 0 ]; then
		symbol="RUN"
	elif [ "$display_status" -ne 0 ]; then
		symbol="FAIL"
	else
		symbol="OK"
	fi
	if [ "$unicode_output" -eq 1 ]; then
		if [ "$state" = RUN ] && [ "$display_status" -eq 0 ]; then
			symbol="•"
		elif [ "$display_status" -eq 0 ]; then
			symbol="✓"
		else
			symbol="✗"
		fi
	fi
	if [ "$live_output" -eq 1 ] ||
		{ [ "${PROFILE_SETUP_OUTPUT_TTY:-}" = 1 ] && [ "$SETUP_PROGRESS_COLUMNS" -gt 0 ]; } ||
		{ [ -z "${PROFILE_SETUP_OUTPUT_TTY:-}" ] && [ -t 1 ] && [ "$SETUP_PROGRESS_COLUMNS" -gt 0 ]; }; then
		terminal_columns="$SETUP_PROGRESS_COLUMNS"
		if [ "$terminal_columns" -le "${#count}" ]; then
			SETUP_PROGRESS_LINE="${count:0:terminal_columns}"
			return
		fi
		fixed_width=$((10 + ${#count} + ${#symbol}))
		if [ "$terminal_columns" -lt $((fixed_width + width + 1 + ${#live_label})) ]; then
			live_label=""
		fi
		available_width=$((terminal_columns - fixed_width))
		if [ -z "$live_label" ] && [ "$available_width" -lt "$width" ]; then
			width="$available_width"
		fi
		if [ "$width" -lt 1 ]; then
			compact_output=1
			width=$((terminal_columns - ${#count} - 1))
			if [ "$width" -lt 1 ]; then
				width=1
			fi
		fi
	fi
	filled=$((SETUP_PROGRESS_CURRENT * width / SETUP_PROGRESS_TOTAL))
	remaining=$((width - filled))
	if [ "$SETUP_PROGRESS_CURRENT" -lt "$SETUP_PROGRESS_TOTAL" ]; then
		head="$head_char"
		remaining=$((remaining - 1))
	fi
	for ((ix = 0; ix < filled; ix++)); do
		completed_bar+="$completed_char"
	done
	for ((ix = 0; ix < remaining; ix++)); do
		remaining_bar+="$remaining_char"
	done

	if [ "$live_output" -eq 1 ] && [ -z "${NO_COLOR:-}" ]; then
		bar_colour=$'\033[1;92m'
		remaining_colour=$'\033[90m'
		colour_reset=$'\033[0m'
		if [ "$display_status" -eq 0 ]; then
			status_colour="$bar_colour"
		else
			status_colour=$'\033[1;91m'
		fi
	fi
	if [ "$compact_output" -eq 1 ]; then
		printf -v progress_line '%b%s%s%b%s%b %s' \
			"$bar_colour" "$completed_bar" "$head" "$remaining_colour" "$remaining_bar" \
			"$colour_reset" "$count"
	elif [ "$live_output" -eq 1 ] && [ -z "$live_label" ]; then
		printf -v progress_line '  %b%s%s%b%s%b %3d%% %s %b%s%b' \
			"$bar_colour" "$completed_bar" "$head" "$remaining_colour" "$remaining_bar" \
			"$colour_reset" "$percent" "$count" "$status_colour" "$symbol" "$colour_reset"
	else
		printf -v progress_line '  %b%s%s%b%s%b %3d%% %s %b%s%b %s' \
			"$bar_colour" "$completed_bar" "$head" "$remaining_colour" "$remaining_bar" \
			"$colour_reset" "$percent" "$count" "$status_colour" "$symbol" "$colour_reset" \
			"$live_label"
	fi
	SETUP_PROGRESS_LINE="$progress_line"
}

setup_progress_render() {
	local sequence

	SETUP_PROGRESS_LABEL="$1"
	SETUP_PROGRESS_STATE="$2"
	setup_progress_build_line "$1" "$2"
	sequence="${SETUP_PROGRESS_SC}${SETUP_PROGRESS_CUP_FOOTER}${SETUP_PROGRESS_EL}${SETUP_PROGRESS_LINE}${SETUP_PROGRESS_RC}"
	setup_progress_write "$sequence"
	setup_progress_record_state
}

setup_progress_begin() {
	if [ "$SETUP_PROGRESS_TOTAL" -le 0 ]; then
		return
	fi
	if setup_progress_pin; then
		setup_progress_render "$1" RUN
	fi
}

setup_progress_advance() {
	local label="$1"
	local exit_code="$2"

	if [ "$SETUP_PROGRESS_TOTAL" -le 0 ]; then
		return
	fi
	SETUP_PROGRESS_CURRENT=$((SETUP_PROGRESS_CURRENT + 1))
	if [ "$exit_code" -ne 0 ]; then
		SETUP_PROGRESS_FAILED=1
	fi
	if [ "$SETUP_PROGRESS_PINNED" -eq 1 ]; then
		setup_progress_render "$label" OK
		if [ "$SETUP_PROGRESS_CURRENT" -eq "$SETUP_PROGRESS_TOTAL" ]; then
			setup_progress_finish
		fi
		return
	fi
	setup_progress_build_line "$label" OK
	printf '%s\n' "$SETUP_PROGRESS_LINE"
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
	# Gather optional profile values before package installation.
	GIT_USER_NAME=$(git config --global user.name 2>/dev/null) || GIT_USER_NAME=""
	GIT_USER_EMAIL=$(git config --global user.email 2>/dev/null) || GIT_USER_EMAIL=""
	GIT_USER_PHONE=$(git config --global user.phonenumber 2>/dev/null) || GIT_USER_PHONE=""

	if [ -z "$GIT_USER_NAME" ]; then
		read -r -p "Enter github username: " GIT_USER_NAME
	fi
	read -r -p "Enter github email address (leave blank to keep the existing value): " input
	if [ ! -z "$input" ]; then
		GIT_USER_EMAIL="$input"
	fi
	read -r -p "Enter phone number (leave blank to keep the existing value): " input
	if [ ! -z "$input" ]; then
		GIT_USER_PHONE="$input"
	fi
	echo ""
	log "All profile input collected. Setup will continue."
}

run_function() {
	local func_name=$1 exit_code=0
	local had_errexit=0

	# Calling a function directly from `cmd || ...` disables errexit for every
	# command in that function. Run it in a subshell instead so the first
	# unhandled error is reported, while the parent can continue to the next
	# setup step. Setup functions persist their changes on disk; any environment
	# needed by later steps must be refreshed by the caller.
	case $- in
	*e*) had_errexit=1 ;;
	esac

	setup_progress_begin "$func_name"
	if command -v gum >/dev/null 2>&1; then
		gum style --foreground 212 --bold ">>> $func_name"
	else
		echo ">>> $func_name"
	fi

	set +e
	(
		set -E
		set -e
		set -o pipefail
		trap 'handle_error $LINENO' ERR
		if [ "${PROFILE_SETUP_PROGRESS_FD:-}" = 9 ]; then
			"$func_name" 9>&-
		else
			"$func_name"
		fi
	)
	exit_code=$?
	if [ "$had_errexit" -eq 1 ]; then
		set -e
	fi

	if [ "$exit_code" -ne 0 ]; then
		failed_functions+=("$func_name")
		if command -v gum >/dev/null 2>&1; then
			gum style --foreground 196 --bold "FAIL $func_name"
		else
			echo "Warning: $func_name failed, continuing with next function..."
		fi
	elif command -v gum >/dev/null 2>&1; then
		gum style --foreground 82 --bold "<<< $func_name done"
	else
		echo "<<< $func_name done"
	fi
	setup_progress_advance "$func_name" "$exit_code"
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
	local setup_status=0
	# Stop the sudo keepalive explicitly before returning or replacing this process.
	stop_sudo_keepalive
	ensure_directory
	if [ ${#failed_functions[@]} -eq 0 ]; then
		echo "==============================="
		echo "       Setup Complete          "
		echo "==============================="
	else
		echo "==============================="
		echo "       Setup Failed            "
		echo "==============================="
		setup_status=1
	fi
	if [ "${PROFILE_SETUP_NO_LOGIN_SHELL:-0}" = 1 ]; then
		return "$setup_status"
	fi
	if [ "$setup_status" -ne 0 ]; then
		return "$setup_status"
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
