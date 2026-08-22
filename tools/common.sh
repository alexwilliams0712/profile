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
		trap 'if [ -n "$sleep_pid" ]; then kill "$sleep_pid" 2>/dev/null || true; wait "$sleep_pid" 2>/dev/null || true; fi; exit 0' HUP INT TERM
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

log() {
	echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

SETUP_PROGRESS_CURRENT=0
SETUP_PROGRESS_TOTAL=0
SETUP_PROGRESS_FAILED=0
SETUP_PROGRESS_ENABLED=0
SETUP_PROGRESS_PINNED=0
SETUP_PROGRESS_OWNS_FD=0
SETUP_PROGRESS_SPINNER_PID=""
SETUP_PROGRESS_STARTED=0
SETUP_PROGRESS_STEP_STARTED=0
SETUP_PROGRESS_STEP_LABEL=""
SETUP_PROGRESS_STEP_STATE=run
SETUP_PROGRESS_ROWS=0
SETUP_PROGRESS_COLUMNS=0
SETUP_PROGRESS_LABEL_WIDTH=28
SETUP_PROGRESS_BAR_WIDTH=24
SETUP_PROGRESS_BLUE=""
SETUP_PROGRESS_GREEN=""
SETUP_PROGRESS_RED=""
SETUP_PROGRESS_MUTED=""
SETUP_PROGRESS_RESET=""

setup_progress_start() {
	SETUP_PROGRESS_CURRENT=0
	SETUP_PROGRESS_TOTAL=$#
	SETUP_PROGRESS_FAILED=0
	SETUP_PROGRESS_ENABLED=0
	SETUP_PROGRESS_PINNED=0
	SETUP_PROGRESS_SPINNER_PID=""
	SETUP_PROGRESS_STARTED=$SECONDS
	SETUP_PROGRESS_BLUE=""
	SETUP_PROGRESS_GREEN=""
	SETUP_PROGRESS_RED=""
	SETUP_PROGRESS_MUTED=""
	SETUP_PROGRESS_RESET=""

	# The entry point may update itself before launching this script, leaving its
	# old in-memory code unable to pass the terminal through on that first run.
	if [ "$SETUP_PROGRESS_TOTAL" -gt 0 ] &&
		[ "${TERM:-dumb}" != dumb ] &&
		[ ! -t 9 ] &&
		{ exec 9<>/dev/tty; } 2>/dev/null; then
		PROFILE_SETUP_OUTPUT_TTY=1
		PROFILE_SETUP_PROGRESS_FD=9
		PROFILE_SETUP_DEFER_PROGRESS_FINISH=0
		SETUP_PROGRESS_OWNS_FD=1
	fi
	if [ "$SETUP_PROGRESS_TOTAL" -gt 0 ] &&
		[ "${PROFILE_SETUP_OUTPUT_TTY:-0}" = 1 ] &&
		[ "${PROFILE_SETUP_PROGRESS_FD:-}" = 9 ] &&
		[ "${TERM:-dumb}" != dumb ] &&
		(: >&9) 2>/dev/null; then
		SETUP_PROGRESS_ENABLED=1
	fi
	if [ "$SETUP_PROGRESS_ENABLED" -eq 1 ] && [ -z "${NO_COLOR:-}" ]; then
		SETUP_PROGRESS_BLUE=$'\033[38;2;108;142;168m'
		SETUP_PROGRESS_GREEN=$'\033[38;2;155;179;150m'
		SETUP_PROGRESS_RED=$'\033[38;2;237;158;152m'
		SETUP_PROGRESS_MUTED=$'\033[38;2;106;102;94m'
		SETUP_PROGRESS_RESET=$'\033[0m'
	fi
}

setup_progress_write() {
	printf '%b' "$@" >&9 2>/dev/null || true
}

setup_progress_read_dimensions() {
	local size rows columns label_width=28 bar_width=24

	size="$(stty size <&9 2>/dev/null)" || return 1
	rows=${size%% *}
	columns=${size##* }
	case "$rows:$columns" in
	*[!0-9:]* | :* | *:) return 1 ;;
	esac
	SETUP_PROGRESS_ROWS=$rows
	SETUP_PROGRESS_COLUMNS=$columns
	if [ "$rows" -lt 5 ] || [ "$columns" -lt 46 ]; then
		return 1
	fi
	if [ "$columns" -lt 78 ]; then
		label_width=20
		bar_width=$((columns - label_width - 26))
		if [ "$bar_width" -lt 8 ]; then
			label_width=$((label_width - 8 + bar_width))
			bar_width=8
		fi
	fi
	SETUP_PROGRESS_LABEL_WIDTH=$label_width
	SETUP_PROGRESS_BAR_WIDTH=$bar_width
}

setup_progress_clear_footer() {
	local rows=$1

	if [ "$rows" -ge 2 ]; then
		setup_progress_write "\033[$((rows - 1));1H"$'\033[2K' \
			"\033[${rows};1H"$'\033[2K'
	fi
}

setup_progress_apply_pin() {
	local output_row=$((SETUP_PROGRESS_ROWS - 2))
	local step_row=$((SETUP_PROGRESS_ROWS - 1))

	setup_progress_write $'\033[r'"\033[${step_row};1H"$'\033[2K' \
		"\033[${SETUP_PROGRESS_ROWS};1H"$'\033[2K' \
		"\033[1;${output_row}r\033[${output_row};1H"
	SETUP_PROGRESS_PINNED=1
}

setup_progress_pin() {
	setup_progress_read_dimensions || return 1
	setup_progress_apply_pin
}

setup_progress_restore() {
	local step_row=$((SETUP_PROGRESS_ROWS - 1))

	if [ "$SETUP_PROGRESS_PINNED" -ne 1 ]; then
		return
	fi
	setup_progress_write $'\033[r'
	setup_progress_clear_footer "$SETUP_PROGRESS_ROWS"
	setup_progress_write "\033[${step_row};1H"
	SETUP_PROGRESS_PINNED=0
}

setup_progress_refresh_dimensions() {
	local old_rows=$SETUP_PROGRESS_ROWS
	local old_columns=$SETUP_PROGRESS_COLUMNS

	if ! setup_progress_read_dimensions; then
		setup_progress_write $'\033[r'
		setup_progress_clear_footer "$old_rows"
		setup_progress_clear_footer "$SETUP_PROGRESS_ROWS"
		if [ "$SETUP_PROGRESS_ROWS" -ge 2 ]; then
			setup_progress_write "\033[$((SETUP_PROGRESS_ROWS - 1));1H"
		fi
		SETUP_PROGRESS_PINNED=0
		SETUP_PROGRESS_ENABLED=0
		return 1
	fi
	if [ "$old_rows" -ne "$SETUP_PROGRESS_ROWS" ] ||
		[ "$old_columns" -ne "$SETUP_PROGRESS_COLUMNS" ]; then
		setup_progress_write $'\033[r'
		setup_progress_clear_footer "$old_rows"
		setup_progress_apply_pin
	fi
}

setup_progress_line() {
	local kind=$1 state=$2 tick=${3:-0}
	local width=$SETUP_PROGRESS_BAR_WIDTH pulse_width=5 ix filled=0 position=0
	local started="$SETUP_PROGRESS_STEP_STARTED"
	local label=${SETUP_PROGRESS_STEP_LABEL//_/ }
	local colour="$SETUP_PROGRESS_BLUE" icon="●" suffix
	local bar="" bar_colour char timer padded_label percent=0

	if [ "$kind" = overall ]; then
		started="$SETUP_PROGRESS_STARTED"
		label=Overall
		icon="◆"
		filled=$((SETUP_PROGRESS_CURRENT * width / SETUP_PROGRESS_TOTAL))
		percent=$((SETUP_PROGRESS_CURRENT * 100 / SETUP_PROGRESS_TOTAL))
		if [ "$SETUP_PROGRESS_CURRENT" -eq "$SETUP_PROGRESS_TOTAL" ]; then
			state=ok
			[ "$SETUP_PROGRESS_FAILED" -ne 0 ] && state=fail
		fi
	elif [ "$state" = run ]; then
		position=$((tick % ((width - pulse_width) * 2)))
		if [ "$position" -gt $((width - pulse_width)) ]; then
			position=$(((width - pulse_width) * 2 - position))
		fi
	fi
	case "$state" in
	ok)
		colour="$SETUP_PROGRESS_GREEN"
		icon="✓"
		filled=$width
		;;
	fail)
		colour="$SETUP_PROGRESS_RED"
		icon="✗"
		filled=$width
		;;
	esac
	for ((ix = 0; ix < width; ix++)); do
		bar_colour="$SETUP_PROGRESS_MUTED"
		char="─"
		if { [ "$kind" = overall ] && [ "$ix" -lt "$filled" ]; } ||
			{ [ "$kind" = step ] && [ "$state" != run ]; } ||
			{ [ "$kind" = step ] && [ "$ix" -ge "$position" ] && [ "$ix" -lt $((position + pulse_width)) ]; }; then
			bar_colour="$colour"
			char="━"
		fi
		bar="${bar}${bar_colour}${char}"
	done
	printf -v timer '%d:%02d:%02d' \
		$(((SECONDS - started) / 3600)) \
		$((((SECONDS - started) % 3600) / 60)) $(((SECONDS - started) % 60))
	if [ "$kind" = overall ]; then
		printf -v suffix '%3d%% %d/%d %s' "$percent" "$SETUP_PROGRESS_CURRENT" \
			"$SETUP_PROGRESS_TOTAL" "$timer"
	elif [ "$state" = run ]; then
		suffix=$timer
	elif [ "$state" = ok ]; then
		suffix="100% $timer"
	else
		suffix="FAIL $timer"
	fi
	printf -v padded_label "%-${SETUP_PROGRESS_LABEL_WIDTH}.${SETUP_PROGRESS_LABEL_WIDTH}s" "$label"
	printf -v SETUP_PROGRESS_LINE '  %b%s%b %b%s%b %s%b %s' \
		"$colour" "$icon" "$SETUP_PROGRESS_RESET" "$colour" "$padded_label" \
		"$SETUP_PROGRESS_RESET" "$bar" "$SETUP_PROGRESS_RESET" "$suffix"
}

setup_progress_render() {
	local tick=${1:-0}
	local step_row=$((SETUP_PROGRESS_ROWS - 1))
	local step_line

	setup_progress_line step "$SETUP_PROGRESS_STEP_STATE" "$tick"
	step_line=$SETUP_PROGRESS_LINE
	setup_progress_line overall run
	setup_progress_write $'\0337'"\033[${step_row};1H"$'\033[2K'"${step_line}" \
		"\033[${SETUP_PROGRESS_ROWS};1H"$'\033[2K'"${SETUP_PROGRESS_LINE}"$'\0338'
}

setup_progress_begin_step() {
	local parent_pid=$$

	if [ "$SETUP_PROGRESS_ENABLED" -ne 1 ]; then
		return 1
	fi
	if [ "$SETUP_PROGRESS_PINNED" -ne 1 ] && ! setup_progress_pin; then
		SETUP_PROGRESS_ENABLED=0
		return 1
	fi
	SETUP_PROGRESS_STEP_LABEL=$1
	SETUP_PROGRESS_STEP_STARTED=$SECONDS
	SETUP_PROGRESS_STEP_STATE=run
	setup_progress_render 0
	(
		local tick=0
		while kill -0 "$parent_pid" 2>/dev/null; do
			sleep 0.2
			tick=$((tick + 1))
			if [ $((tick % 5)) -eq 0 ]; then
				setup_progress_refresh_dimensions || exit 0
			fi
			setup_progress_render "$tick"
		done
	) </dev/null >/dev/null 2>&1 &
	SETUP_PROGRESS_SPINNER_PID=$!
}

setup_progress_stop_spinner() {
	if [ -z "$SETUP_PROGRESS_SPINNER_PID" ]; then
		return
	fi
	kill "$SETUP_PROGRESS_SPINNER_PID" 2>/dev/null || true
	wait "$SETUP_PROGRESS_SPINNER_PID" 2>/dev/null || true
	SETUP_PROGRESS_SPINNER_PID=""
}

setup_progress_complete_step() {
	local label=$1
	local exit_code=$2
	local state=ok

	setup_progress_stop_spinner
	SETUP_PROGRESS_CURRENT=$((SETUP_PROGRESS_CURRENT + 1))
	if [ "$exit_code" -ne 0 ]; then
		SETUP_PROGRESS_FAILED=$((SETUP_PROGRESS_FAILED + 1))
		state=fail
	fi
	SETUP_PROGRESS_STEP_LABEL=$label
	SETUP_PROGRESS_STEP_STATE=$state
	if setup_progress_refresh_dimensions; then
		setup_progress_render
		setup_progress_line step "$state"
		printf '%s\n' "$SETUP_PROGRESS_LINE"
	else
		setup_step_message "$state" "$label"
	fi
}

setup_progress_pause() {
	setup_progress_stop_spinner
	setup_progress_restore
}

setup_progress_finish() {
	local step_row
	local overall_line

	setup_progress_stop_spinner
	if [ "$SETUP_PROGRESS_PINNED" -eq 1 ]; then
		setup_progress_refresh_dimensions || true
	fi
	if [ "$SETUP_PROGRESS_PINNED" -eq 1 ]; then
		setup_progress_line overall run
		overall_line=$SETUP_PROGRESS_LINE
		if [ "${PROFILE_SETUP_DEFER_PROGRESS_FINISH:-0}" = 1 ]; then
			setup_progress_render
			SETUP_PROGRESS_ENABLED=0
			return
		fi
		step_row=$((SETUP_PROGRESS_ROWS - 1))
		setup_progress_write $'\033[r'"\033[${step_row};1H"$'\033[2K' \
			"\033[${SETUP_PROGRESS_ROWS};1H"$'\033[2K' \
			"\033[${step_row};1H${overall_line}"$'\n'
	fi
	SETUP_PROGRESS_PINNED=0
	SETUP_PROGRESS_ENABLED=0
	if [ "$SETUP_PROGRESS_OWNS_FD" -eq 1 ]; then
		exec 9>&-
		SETUP_PROGRESS_OWNS_FD=0
	fi
}

setup_progress_interrupt() {
	local status=$1
	PROFILE_SETUP_DEFER_PROGRESS_FINISH=0
	setup_progress_finish
	exit "$status"
}

setup_progress_install_traps() {
	trap 'setup_progress_finish; stop_sudo_keepalive' EXIT
	trap 'setup_progress_interrupt 129' HUP
	trap 'setup_progress_interrupt 130' INT
	trap 'setup_progress_interrupt 143' TERM
}

setup_step_message() {
	local state=$1
	local label=$2
	local colour=""
	local reset=""
	local message=">>> $label"

	case "$state" in
	ok) message="<<< $label done" ;;
	fail) message="FAIL $label" ;;
	esac
	if { [ -t 1 ] || [ "${PROFILE_SETUP_OUTPUT_TTY:-0}" = 1 ]; } &&
		[ "${TERM:-dumb}" != dumb ] && [ -z "${NO_COLOR:-}" ]; then
		reset=$'\033[0m'
		case "$state" in
		start) colour=$'\033[38;2;108;142;168m' ;;
		ok) colour=$'\033[38;2;155;179;150m' ;;
		fail) colour=$'\033[38;2;237;158;152m' ;;
		esac
	fi
	printf '%b%s%b\n' "$colour" "$message" "$reset"
}

run_functions() {
	local func_name

	for func_name in "$@"; do
		run_function "$func_name"
	done
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
	local progress_enabled=0

	# Calling a function directly from `cmd || ...` disables errexit for every
	# command in that function. Run it in a subshell instead so the first
	# unhandled error is reported, while the parent can continue to the next
	# setup step. Setup functions persist their changes on disk; any environment
	# needed by later steps must be refreshed by the caller.
	case $- in
	*e*) had_errexit=1 ;;
	esac

	if setup_progress_begin_step "$func_name"; then
		progress_enabled=1
	fi
	setup_step_message start "$func_name"

	set +e
	(
		set -E
		set -e
		set -o pipefail
		trap 'handle_error $LINENO' ERR
		"$func_name"
	) 9>&-
	exit_code=$?
	if [ "$had_errexit" -eq 1 ]; then
		set -e
	fi

	if [ "$exit_code" -ne 0 ]; then
		failed_functions+=("$func_name")
	fi
	if [ "$progress_enabled" -eq 1 ]; then
		setup_progress_complete_step "$func_name" "$exit_code"
	elif [ "$exit_code" -ne 0 ]; then
		setup_step_message fail "$func_name"
	else
		setup_step_message ok "$func_name"
	fi
	return 0
}

set_git_config() {
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

copy_shared_dotfiles() {
	mkdir -p "$HOME/.config/btop/themes" "$HOME/.local/bin"
	cp "$PROFILE_DIR/dotfiles/starship.toml" "$HOME/.config/starship.toml"
	cp "$PROFILE_DIR/dotfiles/btop/themes/armada-deep.theme" "$HOME/.config/btop/themes/armada-deep.theme"
	cp "$PROFILE_DIR/dotfiles/btop/btop.conf" "$HOME/.config/btop/btop.conf"
	cp "$PROFILE_DIR/dotfiles/.profile" "$HOME/.profile"
	cp "$PROFILE_DIR/VERSION" "$HOME/BASH_PROFILE_VERSION"
	cp "$PROFILE_DIR/dotfiles/.bashrc" "$HOME/.bashrc"
	cp "$PROFILE_DIR/dotfiles/.prettierrc" "$HOME/.prettierrc"
	cp "$PROFILE_DIR/dotfiles/.bash_aliases" "$HOME/.bash_aliases"
	cp "$PROFILE_DIR/dotfiles/.inputrc" "$HOME/.inputrc"
	cp "$PROFILE_DIR/dotfiles/bin/json_formatter.py" "$HOME/.local/bin/json_formatter.py"
	cp "$PROFILE_DIR/dotfiles/bin/work-proxy" "$HOME/.local/bin/work-proxy"
	chmod +x "$HOME/.local/bin/json_formatter.py" "$HOME/.local/bin/work-proxy"
}

install_starship() {
	curl -sS https://starship.rs/install.sh | sh -s -- -y
	if command -v starship >/dev/null 2>&1; then
		starship --version
	fi
}

install_foundry() {
	# Foundry (forge, cast, anvil, chisel) via the official installer — NOT snap.
	# foundryup installs to ~/.foundry/bin (added to PATH in .bashrc).
	curl -L https://foundry.paradigm.xyz | bash
	"$HOME/.foundry/bin/foundryup"
	"$HOME/.foundry/bin/cast" --version
}

install_rust() {
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

}

install_ai() {
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
	local setup_status=0
	setup_progress_finish
	# Stop the sudo keepalive explicitly before returning or replacing this process.
	stop_sudo_keepalive
	cd "$PROFILE_DIR"
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
