#!/bin/bash
# Shared functions used by both setup_macos.sh and setup_ubuntu.sh

export DEFAULT_PYTHON_VERSION="3.14.5"

handle_error() {
	echo "An error occurred on line $1"
}

# Keep Linux sudo authorisation alive; Homebrew resets macOS timestamps.
SUDO_KEEPALIVE_PID=""
sudo_command() {
	/usr/bin/sudo "$@"
}

keep_sudo_alive() {
	local parent_pid=$$

	if [ -n "$SUDO_KEEPALIVE_PID" ] && kill -0 "$SUDO_KEEPALIVE_PID" 2>/dev/null; then
		return 0
	fi
	sudo_command -v || return 1
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
SETUP_PROGRESS_SPINNER_PID=""
SETUP_PROGRESS_STARTED=0
SETUP_PROGRESS_STEP_STARTED=0
SETUP_PROGRESS_STEP_LABEL=""
SETUP_PROGRESS_STEP_STATE=run
SETUP_PROGRESS_STEPS=()
SETUP_PROGRESS_STATES=()
SETUP_PROGRESS_TIMES=()
SETUP_PROGRESS_FOOTER_ROWS=2
SETUP_PROGRESS_GRID_COLUMNS=0
SETUP_PROGRESS_CELL_WIDTH=0
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
	SETUP_PROGRESS_STEPS=("$@")
	SETUP_PROGRESS_STATES=()
	SETUP_PROGRESS_TIMES=()
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
		{ : </dev/tty >/dev/tty; } 2>/dev/null; then
		PROFILE_SETUP_OUTPUT_TTY=1
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
	printf '%b' "$@" >/dev/tty 2>/dev/null || true
}

setup_progress_read_dimensions() {
	local size rows columns label_width=28 bar_width=24

	size="$(stty size </dev/tty 2>/dev/null)" || return 1
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
	SETUP_PROGRESS_GRID_COLUMNS=$(((SETUP_PROGRESS_TOTAL + rows - 5) / (rows - 4)))
	SETUP_PROGRESS_FOOTER_ROWS=2
	if [ "$SETUP_PROGRESS_GRID_COLUMNS" -gt 0 ] &&
		[ $((columns / SETUP_PROGRESS_GRID_COLUMNS)) -ge 40 ]; then
		SETUP_PROGRESS_CELL_WIDTH=$((columns / SETUP_PROGRESS_GRID_COLUMNS))
		SETUP_PROGRESS_FOOTER_ROWS=$(((SETUP_PROGRESS_TOTAL + SETUP_PROGRESS_GRID_COLUMNS - 1) / SETUP_PROGRESS_GRID_COLUMNS + 1))
	else
		SETUP_PROGRESS_GRID_COLUMNS=0
	fi
	SETUP_PROGRESS_LABEL_WIDTH=$label_width
	SETUP_PROGRESS_BAR_WIDTH=$bar_width
}

setup_progress_clear_footer() {
	local rows=$1 height=${2:-$SETUP_PROGRESS_FOOTER_ROWS} row

	for ((row = rows - height + 1; row <= rows; row++)); do
		[ "$row" -gt 0 ] && setup_progress_write "\033[${row};1H"$'\033[2K'
	done
}

setup_progress_apply_pin() {
	local output_row=$((SETUP_PROGRESS_ROWS - SETUP_PROGRESS_FOOTER_ROWS))

	setup_progress_write $'\033[r'
	setup_progress_clear_footer "$SETUP_PROGRESS_ROWS"
	setup_progress_write "\033[1;${output_row}r\033[${output_row};1H"
	SETUP_PROGRESS_PINNED=1
}

setup_progress_pin() {
	setup_progress_read_dimensions || return 1
	setup_progress_apply_pin
}

setup_progress_restore() {
	local step_row=$((SETUP_PROGRESS_ROWS - SETUP_PROGRESS_FOOTER_ROWS + 1))

	if [ "$SETUP_PROGRESS_PINNED" -ne 1 ]; then
		return
	fi
	setup_progress_write $'\033[r'
	setup_progress_clear_footer "$SETUP_PROGRESS_ROWS"
	setup_progress_write "\033[${step_row};1H"
	SETUP_PROGRESS_PINNED=0
}

setup_progress_refresh_dimensions() {
	local old_rows=$SETUP_PROGRESS_ROWS old_height=$SETUP_PROGRESS_FOOTER_ROWS
	local old_columns=$SETUP_PROGRESS_COLUMNS

	if ! setup_progress_read_dimensions; then
		setup_progress_write $'\033[r'
		setup_progress_clear_footer "$old_rows" "$old_height"
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
		setup_progress_clear_footer "$old_rows" "$old_height"
		setup_progress_apply_pin
	fi
}

setup_progress_line() {
	local kind=$1 state=$2 tick=${3:-0} elapsed=${4:-$((SECONDS - SETUP_PROGRESS_STEP_STARTED))}
	local width=$SETUP_PROGRESS_BAR_WIDTH pulse_width=5 ix filled=0 position=0
	local label=${SETUP_PROGRESS_STEP_LABEL//_/ }
	local colour="$SETUP_PROGRESS_BLUE" icon="●" suffix
	local bar="" bar_colour char timer padded_label percent=0

	if [ "$kind" = overall ]; then
		elapsed=$((SECONDS - SETUP_PROGRESS_STARTED))
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
	pending)
		colour="$SETUP_PROGRESS_MUTED"
		icon="○"
		;;
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
			{ [ "$kind" = step ] && { [ "$state" = ok ] || [ "$state" = fail ]; }; } ||
			{ [ "$kind" = step ] && [ "$state" = run ] && [ "$ix" -ge "$position" ] && [ "$ix" -lt $((position + pulse_width)) ]; }; then
			bar_colour="$colour"
			char="━"
		fi
		bar="${bar}${bar_colour}${char}"
	done
	printf -v timer '%d:%02d:%02d' \
		$((elapsed / 3600)) \
		$(((elapsed % 3600) / 60)) $((elapsed % 60))
	if [ "$kind" = overall ]; then
		printf -v suffix '%3d%% %d/%d %s' "$percent" "$SETUP_PROGRESS_CURRENT" \
			"$SETUP_PROGRESS_TOTAL" "$timer"
	elif [ "$state" = pending ]; then
		suffix="  0%"
	elif [ "$state" = run ]; then
		suffix=$timer
	elif [ "$state" = ok ]; then
		suffix="100% $timer"
	else
		suffix="FAIL $timer"
	fi
	if [ "$kind" = step ] && [ "${SETUP_PROGRESS_COMPACT:-0}" -eq 1 ]; then
		case "$state" in
		run) suffix=" ..." ;;
		ok) suffix="100%" ;;
		fail) suffix="FAIL" ;;
		esac
	fi
	printf -v padded_label "%-${SETUP_PROGRESS_LABEL_WIDTH}.${SETUP_PROGRESS_LABEL_WIDTH}s" "$label"
	printf -v SETUP_PROGRESS_LINE '  %b%s%b %b%s%b %s%b %s' \
		"$colour" "$icon" "$SETUP_PROGRESS_RESET" "$colour" "$padded_label" \
		"$SETUP_PROGRESS_RESET" "$bar" "$SETUP_PROGRESS_RESET" "$suffix"
}

setup_progress_render() {
	local tick=${1:-0} ix row column elapsed state output=$'\0337'
	local label_width=$SETUP_PROGRESS_LABEL_WIDTH bar_width=$SETUP_PROGRESS_BAR_WIDTH
	local step_row=$((SETUP_PROGRESS_ROWS - SETUP_PROGRESS_FOOTER_ROWS + 1))
	local SETUP_PROGRESS_STEP_LABEL=$SETUP_PROGRESS_STEP_LABEL
	local SETUP_PROGRESS_LABEL_WIDTH=$SETUP_PROGRESS_LABEL_WIDTH
	local SETUP_PROGRESS_BAR_WIDTH=$SETUP_PROGRESS_BAR_WIDTH
	local SETUP_PROGRESS_COMPACT=0

	if [ "$SETUP_PROGRESS_GRID_COLUMNS" -gt 0 ]; then
		SETUP_PROGRESS_COMPACT=1
		SETUP_PROGRESS_LABEL_WIDTH=22
		SETUP_PROGRESS_BAR_WIDTH=$((SETUP_PROGRESS_CELL_WIDTH - 32))
		[ "$SETUP_PROGRESS_BAR_WIDTH" -gt 24 ] && SETUP_PROGRESS_BAR_WIDTH=24
		for ((row = step_row; row < SETUP_PROGRESS_ROWS; row++)); do
			output+="\033[${row};1H"$'\033[2K'
		done
		for ((ix = 0; ix < SETUP_PROGRESS_TOTAL; ix++)); do
			SETUP_PROGRESS_STEP_LABEL=${SETUP_PROGRESS_STEPS[ix]}
			state=${SETUP_PROGRESS_STATES[ix]:-pending}
			elapsed=${SETUP_PROGRESS_TIMES[ix]:-0}
			[ "$state" = run ] && elapsed=$((SECONDS - SETUP_PROGRESS_STEP_STARTED))
			setup_progress_line step "$state" "$tick" "$elapsed"
			row=$((step_row + ix / SETUP_PROGRESS_GRID_COLUMNS))
			column=$((1 + (ix % SETUP_PROGRESS_GRID_COLUMNS) * SETUP_PROGRESS_CELL_WIDTH))
			output+="\033[${row};${column}H${SETUP_PROGRESS_LINE}"
		done
	else
		setup_progress_line step "$SETUP_PROGRESS_STEP_STATE" "$tick"
		output+="\033[${step_row};1H"$'\033[2K'"${SETUP_PROGRESS_LINE}"
	fi
	SETUP_PROGRESS_LABEL_WIDTH=$label_width
	SETUP_PROGRESS_BAR_WIDTH=$bar_width
	setup_progress_line overall run
	setup_progress_write "${output}\033[${SETUP_PROGRESS_ROWS};1H"$'\033[2K'"${SETUP_PROGRESS_LINE}"$'\0338'
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
	SETUP_PROGRESS_STATES[SETUP_PROGRESS_CURRENT]=run
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
	if [ "$exit_code" -ne 0 ]; then
		SETUP_PROGRESS_FAILED=$((SETUP_PROGRESS_FAILED + 1))
		state=fail
	fi
	SETUP_PROGRESS_STEP_LABEL=$label
	SETUP_PROGRESS_STEP_STATE=$state
	SETUP_PROGRESS_STATES[SETUP_PROGRESS_CURRENT]=$state
	SETUP_PROGRESS_TIMES[SETUP_PROGRESS_CURRENT]=$((SECONDS - SETUP_PROGRESS_STEP_STARTED))
	SETUP_PROGRESS_CURRENT=$((SETUP_PROGRESS_CURRENT + 1))
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
		step_row=$((SETUP_PROGRESS_ROWS - SETUP_PROGRESS_FOOTER_ROWS + 1))
		setup_progress_write $'\033[r'
		setup_progress_clear_footer "$SETUP_PROGRESS_ROWS"
		setup_progress_write "\033[${step_row};1H${overall_line}"$'\n'
	fi
	SETUP_PROGRESS_PINNED=0
	SETUP_PROGRESS_ENABLED=0
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

setup_tool_path() {
	export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.pyenv/bin:$HOME/.pyenv/shims:$HOME/.npm-global/bin:$HOME/.foundry/bin:$HOME/go/bin:/usr/local/go/bin:$PATH"
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
		# Earlier steps install these tools in subprocesses; refresh their PATH.
		setup_tool_path
		if [ "${PROFILE_SETUP_PROGRESS_FD:-}" = 9 ] && [ -t 9 ]; then
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

	if command -v delta >/dev/null 2>&1; then
		git config --global core.pager delta
		git config --global interactive.diffFilter 'delta --color-only'
		git config --global delta.navigate true
		git config --global delta.side-by-side true
		git config --global delta.line-numbers true
	fi

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

configure_espanso_matches() {
	local output=$1 temporary email name phone
	email="$(git config --global user.email)" || email=""
	name="$(git config --global user.name)" || name=""
	phone="$(git config --global user.phonenumber)" || phone=""
	temporary="$(mktemp "${output}.XXXXXX")" || return 1
	# JSON strings are valid YAML scalars and escape quotes, slashes and newlines.
	if ! PROFILE_ESPANSO_EMAIL="$email" PROFILE_ESPANSO_NAME="$name" PROFILE_ESPANSO_PHONE="$phone" \
		perl -MJSON::PP -MEncode=decode -pe '
			BEGIN {
				my $json = JSON::PP->new->utf8->allow_nonref;
				%values = map {
					my $value = $json->encode(decode("UTF-8", $ENV{"PROFILE_ESPANSO_" . $_}));
					$value =~ s/\xC2\x85/\\u0085/g;
					$value =~ s/\xE2\x80\xA8/\\u2028/g;
					$value =~ s/\xE2\x80\xA9/\\u2029/g;
					$_ => $value
				} qw(EMAIL NAME PHONE);
				$values{GIT_USER} = $values{NAME};
			}
			s/"__(EMAIL|GIT_USER|PHONE)__"/$values{$1}/g;
		' "$PROFILE_DIR/dotfiles/espanso_match_file.yml" >"$temporary"; then
		rm -f "$temporary"
		return 1
	fi
	mv -f "$temporary" "$output"
}

install_starship() {
	curl -fsS https://starship.rs/install.sh | sh -s -- -y
	if command -v starship >/dev/null 2>&1; then
		starship --version
	fi
}

install_foundry() {
	curl -fsSL https://foundry.paradigm.xyz | bash
	"$HOME/.foundry/bin/foundryup"
	"$HOME/.foundry/bin/cast" --version
}

install_rust() {
	# Keep rustup beside its proxies; Homebrew upgrades can leave them dangling.
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
	local os_type expected_arch hw_arch dependency prefix
	os_type="$(uname -s)"
	export PYENV_ROOT="$HOME/.pyenv"
	export PATH="$PYENV_ROOT/bin:$PATH"
	local python_bin="$PYENV_ROOT/versions/$DEFAULT_PYTHON_VERSION/bin/python"

	if [ "$os_type" = Darwin ]; then
		expected_arch="$(uname -m)"
		hw_arch="$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)"
		if [ "$hw_arch" = 1 ] && [ "$expected_arch" = x86_64 ]; then
			log "Running under Rosetta; rerun natively: arch -arm64 bash setup_entry.sh"
			return 1
		fi
	fi

	# Homebrew owns pyenv on macOS; preserve an incomplete local installation.
	if ! command -v pyenv >/dev/null 2>&1; then
		if [ -d "$PYENV_ROOT" ]; then
			log "Incomplete pyenv installation at $PYENV_ROOT; preserve or move it before retrying."
			return 1
		fi
		curl -fsSL https://pyenv.run | bash
	fi
	eval "$(pyenv init --path)"
	eval "$(pyenv init -)"
	if [ "$os_type" != Darwin ]; then
		pyenv update
	fi

	if [ -d "${python_bin%/bin/python}" ] &&
		{ [ ! -x "$python_bin" ] ||
			{ [ "$os_type" = Darwin ] && ! file -L "$python_bin" | grep -w "$expected_arch" >/dev/null; }; }; then
		log "Removing incomplete or mismatched Python $DEFAULT_PYTHON_VERSION"
		pyenv uninstall -f "$DEFAULT_PYTHON_VERSION"
	fi
	if [ ! -x "$python_bin" ]; then
		if [ "$os_type" = Darwin ]; then
			export ARCHFLAGS="-arch $expected_arch"
			LDFLAGS="" CPPFLAGS="" PKG_CONFIG_PATH=""
			for dependency in openssl readline sqlite3 zlib; do
				prefix="$(brew --prefix "$dependency")"
				LDFLAGS+=" -L$prefix/lib"
				CPPFLAGS+=" -I$prefix/include"
				PKG_CONFIG_PATH+="${PKG_CONFIG_PATH:+:}$prefix/lib/pkgconfig"
			done
			export LDFLAGS CPPFLAGS PKG_CONFIG_PATH
		fi
		pyenv install -s "$DEFAULT_PYTHON_VERSION"
	fi
	if [ ! -x "$python_bin" ]; then
		log "Python $DEFAULT_PYTHON_VERSION installation is incomplete"
		return 1
	fi
	pyenv global "$DEFAULT_PYTHON_VERSION"

	local venv_folder="$PYENV_ROOT/plugins/pyenv-virtualenv"
	if [ ! -d "$venv_folder" ]; then
		git clone https://github.com/pyenv/pyenv-virtualenv.git "$venv_folder"
	else
		git -C "$venv_folder" pull --ff-only https://github.com/pyenv/pyenv-virtualenv.git
	fi
	if [ "$os_type" != Darwin ]; then
		curl -LsSf https://astral.sh/uv/install.sh | sh
	fi
	export PATH="$HOME/.local/bin:$PATH"
	uv pip install --python "$python_bin" pip-tools psutil
	if [ "$os_type" = Darwin ] && [ ! -d "$HOME/.venv" ]; then
		uv venv --python "$python_bin" "$HOME/.venv"
	fi
}

install_npm_packages() {
	if [ "$(uname -s)" = Darwin ]; then
		npm install -g "$@"
	else
		sudo npm install -g "$@"
	fi
}

configure_node() {
	local dir packages=(wscat json5 fracturedjsonjs)
	if [ "$(uname -s)" = Darwin ]; then
		for dir in "$HOME/.npm" "$HOME/.npm-global"; do
			if [ -d "$dir" ] &&
				[ -n "$(find "$dir" ! -user "$(id -un)" -print -quit 2>/dev/null)" ]; then
				run_sudo chown -R "$(id -u):$(id -g)" "$dir"
			fi
		done
		mkdir -p "$HOME/.npm-global"
		npm config set prefix "$HOME/.npm-global"
	else
		packages+=(prettier)
	fi
	install_npm_packages "${packages[@]}"
}

install_go_tools() {
	go install github.com/dim13/otpauth@latest
	if [ "$(uname -s)" != Darwin ]; then
		go install github.com/boyter/scc/v3@latest
	fi
}

github_latest_tag() {
	local repo="$1" tag
	tag=$(curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" | jq -r '.tag_name') || return
	if [ -z "$tag" ] || [ "$tag" = null ]; then
		log "Could not fetch latest tag for $repo" >&2
		return 1
	fi
	echo "$tag"
}

install_terraform() (
	local os arch version install_dir installed_binary=terraform target_dir=/usr/local/bin
	case "$(uname -s)" in
	Darwin) os=darwin ;;
	Linux) os=linux ;;
	*)
		log "Unsupported Terraform platform"
		return 1
		;;
	esac
	case "$(uname -m)" in
	x86_64 | amd64) arch=amd64 ;;
	arm64 | aarch64) arch=arm64 ;;
	*)
		log "Unsupported Terraform architecture"
		return 1
		;;
	esac
	version=$(github_latest_tag hashicorp/terraform) || return
	version=${version#v}
	if [ "$os" = linux ]; then
		installed_binary="$target_dir/terraform"
	fi
	if command -v "$installed_binary" >/dev/null 2>&1 &&
		"$installed_binary" version | grep -Fx "Terraform v$version" >/dev/null; then
		return 0
	fi
	install_dir=$(mktemp -d) || return
	trap 'rm -rf "$install_dir"' EXIT
	curl -fsSL "https://releases.hashicorp.com/terraform/$version/terraform_${version}_${os}_${arch}.zip" -o "$install_dir/terraform.zip"
	unzip -oq "$install_dir/terraform.zip" -d "$install_dir"
	if [ "$os" = linux ]; then
		sudo install -m 0755 "$install_dir/terraform" "$target_dir/terraform"
	else
		if [ ! -d "$target_dir" ] || [ ! -w "$target_dir" ]; then
			target_dir="$HOME/.local/bin"
			mkdir -p "$target_dir"
		fi
		install -m 0755 "$install_dir/terraform" "$target_dir/terraform"
	fi
	"$target_dir/terraform" version
)

install_ai() {
	curl -fsSL https://claude.ai/install.sh | bash
	curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh
	install_npm_packages @google/gemini-cli
}

exit_script() {
	local setup_status=0
	setup_progress_finish
	stop_sudo_keepalive
	cd "$PROFILE_DIR"
	if [ ${#failed_functions[@]} -eq 0 ]; then
		log "Setup complete."
	else
		printf '\nSetup failed in:\n'
		printf '  %s\n' "${failed_functions[@]}"
		setup_status=1
	fi
	if [ "${PROFILE_SETUP_NO_LOGIN_SHELL:-0}" = 1 ] || [ "$setup_status" -ne 0 ]; then
		return "$setup_status"
	fi
	exec bash -l
}

configure_vscode() {
	# The caller supplies the platform-specific VSCODE_USER_DIR.

	if ! command -v code >/dev/null 2>&1; then
		log "code CLI not found; VS Code configuration failed"
		return 1
	fi

	local vscode_dotfiles="$PROFILE_DIR/dotfiles/vscode"
	local extensions_failed=0 line

	mkdir -p "$VSCODE_USER_DIR"

	cp "$vscode_dotfiles/settings.json" "$VSCODE_USER_DIR/settings.json"

	cp "$vscode_dotfiles/keybindings.json" "$VSCODE_USER_DIR/keybindings.json"

	if [ -f "$vscode_dotfiles/extensions.txt" ]; then
		while IFS= read -r line || [ -n "$line" ]; do
			line=$(echo "$line" | xargs)
			if [ -z "$line" ] || [[ "$line" == \#* ]]; then
				continue
			fi
			if ! code --install-extension "$line" --force; then
				log "Failed to install extension: $line"
				extensions_failed=1
			fi
		done <"$vscode_dotfiles/extensions.txt"
		if [ "$extensions_failed" -eq 0 ]; then
			log "VS Code extensions installed"
		fi
	fi
	return "$extensions_failed"
}
