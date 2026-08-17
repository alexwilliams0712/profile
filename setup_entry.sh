#!/bin/bash

profile_setup_run() {
	local os_name
	os_name="$(uname)"
	export PROFILE_SETUP_NO_LOGIN_SHELL=1

	if [ "$os_name" = "Darwin" ]; then
		# Homebrew revokes cached sudo tickets, so setup_macos requests visible
		# foreground approval only when a privileged step actually needs it.
		:
	else
		sudo -v
	fi

	if [ "$os_name" != "Darwin" ] && ! command -v git >/dev/null 2>&1; then
		echo "git is not installed, installing git."
		sudo apt-get update
		sudo apt-get install -y git
	fi

	# Pull latest version of this repo (non-fatal on first run / auth issues).
	# Apple's /usr/bin/git is only a launcher until the Command Line Tools exist.
	if { [ "$os_name" != "Darwin" ] || xcode-select -p &>/dev/null; } && GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND='ssh -o BatchMode=yes -o ConnectTimeout=10' git fetch origin 2>/dev/null; then
		git reset --hard origin/main
		git checkout main
		GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND='ssh -o BatchMode=yes -o ConnectTimeout=10' git pull
	else
		echo "Warning: could not fetch from remote, continuing with local copy."
	fi

	if [ "$os_name" = "Darwin" ]; then
		bash tools/setup_macos.sh
	elif [ "$os_name" = "Linux" ]; then
		bash tools/setup_ubuntu.sh
	else
		# shellcheck disable=SC1091
		source tools/setup_macos.sh
	fi
}

profile_setup_main() {
	local state_home
	local log_dir
	local log_file
	local status_file
	local progress_file
	local latest_link
	local timestamp
	local setup_status
	local tee_status
	local had_pipefail=0
	local output_tty=0
	local progress_rows
	local progress_columns
	local progress_line
	local progress_summary
	local saved_progress_rows
	local terminal_size
	local terminal_columns
	local progress_csr
	local progress_old_cup
	local progress_cup
	local progress_el

	case "${XDG_STATE_HOME:-}" in
	/*) state_home="$XDG_STATE_HOME" ;;
	*) state_home="$HOME/.local/state" ;;
	esac
	log_dir="${PROFILE_SETUP_LOG_DIR:-$state_home/profile/setup}"
	case "$log_dir" in
	/*) ;;
	*)
		printf 'Error: setup log directory must be absolute: %s\n' "$log_dir" >&2
		unset -f profile_setup_run profile_setup_main
		return 1
		;;
	esac

	if ! timestamp="$(date '+%Y%m%d-%H%M%S')"; then
		printf 'Error: could not determine the setup log timestamp.\n' >&2
		unset -f profile_setup_run profile_setup_main
		return 1
	fi
	if ! mkdir -p "$log_dir" || ! chmod 700 "$log_dir"; then
		printf 'Error: could not prepare setup log directory: %s\n' "$log_dir" >&2
		unset -f profile_setup_run profile_setup_main
		return 1
	fi
	if [ -d "$log_dir/latest.log" ]; then
		printf 'Error: latest setup log path is a directory: %s\n' "$log_dir/latest.log" >&2
		unset -f profile_setup_run profile_setup_main
		return 1
	fi
	if ! log_file="$(umask 077 && mktemp "$log_dir/setup-$timestamp.XXXXXX")" || [ -z "$log_file" ]; then
		printf 'Error: could not create setup log under: %s\n' "$log_dir" >&2
		unset -f profile_setup_run profile_setup_main
		return 1
	fi
	latest_link="$log_dir/.latest-${log_file##*/}"
	if ! chmod 600 "$log_file" ||
		! ln -s "${log_file##*/}" "$latest_link" ||
		! mv -f "$latest_link" "$log_dir/latest.log"; then
		printf 'Error: could not create setup log under: %s\n' "$log_dir" >&2
		rm -f "$latest_link"
		unset -f profile_setup_run profile_setup_main
		return 1
	fi

	if ! printf 'Setup log: %s\n' "$log_file" | tee -a "$log_file"; then
		printf 'Error: could not write setup log: %s\n' "$log_file" >&2
		unset -f profile_setup_run profile_setup_main
		return 1
	fi

	if ! status_file="$(umask 077 && mktemp "$log_dir/.setup-status.XXXXXX")" ||
		[ -z "$status_file" ] || ! chmod 600 "$status_file"; then
		printf 'Error: could not create setup status under: %s\n' "$log_dir" >&2
		unset -f profile_setup_run profile_setup_main
		return 1
	fi
	if ! progress_file="$(umask 077 && mktemp "$log_dir/.setup-progress.XXXXXX")" ||
		[ -z "$progress_file" ] || ! chmod 600 "$progress_file"; then
		printf 'Error: could not create setup progress state under: %s\n' "$log_dir" >&2
		rm -f "$status_file"
		unset -f profile_setup_run profile_setup_main
		return 1
	fi
	if [ -t 1 ]; then
		output_tty=1
	fi
	if set -o | grep -Eq '^pipefail[[:space:]]+on$'; then
		had_pipefail=1
		set +o pipefail
	fi
	if (
		set +e
		export PROFILE_SETUP_OUTPUT_TTY="$output_tty"
		if [ "$output_tty" -eq 1 ]; then
			export PROFILE_SETUP_PROGRESS_FD=9
			export PROFILE_SETUP_PROGRESS_STATE_FILE="$progress_file"
		fi
		profile_setup_run
		setup_status=$?
		printf '%s\n' "$setup_status" >|"$status_file"
		exit "$setup_status"
	) 2>&1 | tee -a "$log_file"; then
		tee_status=0
	else
		tee_status=$?
	fi
	if [ "$had_pipefail" -eq 1 ]; then
		set -o pipefail
	fi
	if ! IFS= read -r setup_status <"$status_file"; then
		setup_status=1
	fi
	rm -f "$status_file"
	case "$setup_status" in
	'' | *[!0-9]*) setup_status=1 ;;
	esac

	if [ "$tee_status" -ne 0 ]; then
		printf 'Error: could not finish writing setup log: %s\n' "$log_file" >&2
		if [ "$setup_status" -eq 0 ]; then
			setup_status="$tee_status"
		fi
	fi
	if ! printf 'Setup log saved to: %s\n' "$log_file" | tee -a "$log_file"; then
		printf 'Error: could not finish writing setup log: %s\n' "$log_file" >&2
		if [ "$setup_status" -eq 0 ]; then
			setup_status=1
		fi
	fi
	if [ "$output_tty" -eq 1 ] && [ -s "$progress_file" ]; then
		progress_rows=""
		progress_columns=""
		progress_line=""
		progress_summary=""
		{
			IFS= read -r progress_rows || true
			IFS= read -r progress_columns || true
			IFS= read -r progress_line || true
			IFS= read -r progress_summary || true
		} <"$progress_file"
		saved_progress_rows="$progress_rows"
		terminal_size="$(stty size <&9 2>/dev/null || true)"
		case "$terminal_size" in
		[0-9]*' '[0-9]*)
			progress_rows="${terminal_size%% *}"
			terminal_columns="${terminal_size##* }"
			;;
		esac
		case "$progress_rows" in
		'' | *[!0-9]* | 0) progress_rows=24 ;;
		esac
		case "$saved_progress_rows" in
		'' | *[!0-9]* | 0) saved_progress_rows="$progress_rows" ;;
		esac
		case "$progress_columns" in
		'' | *[!0-9]* | 0) progress_columns=80 ;;
		esac
		case "${terminal_columns:-}" in
		'' | *[!0-9]* | 0) terminal_columns="$progress_columns" ;;
		esac
		if [ "$terminal_columns" -lt "$progress_columns" ]; then
			progress_line="$(printf '%.*s' "$terminal_columns" "$progress_summary")"
		fi
		if progress_csr="$(tput csr 0 "$((progress_rows - 1))" 2>/dev/null)" &&
			progress_old_cup="$(tput cup "$((saved_progress_rows - 1))" 0 2>/dev/null)" &&
			progress_cup="$(tput cup "$((progress_rows - 1))" 0 2>/dev/null)" &&
			progress_el="$(tput el 2>/dev/null)"; then
			printf '%s%s%s%s%s%s\n' \
				"$progress_csr" "$progress_old_cup" "$progress_el" \
				"$progress_cup" "$progress_el" "$progress_line" >&9 || true
		else
			printf '\033[r' >&9 || true
		fi
	fi
	rm -f "$progress_file"

	unset -f profile_setup_run profile_setup_main
	if [ "$setup_status" -ne 0 ]; then
		return "$setup_status"
	fi

	# Start the replacement login shell only after tee has closed the log.
	bash -l 9>&-
}

profile_setup_main 9>&1
