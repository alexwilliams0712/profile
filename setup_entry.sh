#!/bin/bash

profile_setup_run() {
	local os_name
	local branch
	local worktree_status
	local ID VERSION_ID
	cd -- "$1" || return 1
	os_name="$(uname)" || return 1
	export PROFILE_SETUP_NO_LOGIN_SHELL=1

	if [ "$(id -u)" -eq 0 ]; then
		printf 'Error: run setup as your normal user; privileged steps use sudo.\n' >&2
		return 1
	fi
	case "$os_name" in
	Darwin) ;;
	Linux)
		if [ ! -r /etc/os-release ]; then
			printf 'Error: cannot identify this Linux distribution.\n' >&2
			return 1
		fi
		# shellcheck disable=SC1091
		. /etc/os-release
		if [ "${ID:-}" != ubuntu ] || ! command -v apt-get >/dev/null 2>&1; then
			printf 'Error: Linux setup supports Ubuntu only (detected %s).\n' "${ID:-unknown}" >&2
			return 1
		fi
		if ! dpkg --compare-versions "${VERSION_ID:-0}" ge 24.04; then
			printf 'Error: Ubuntu 24.04 or later is required (detected %s).\n' "${VERSION_ID:-unknown}" >&2
			return 1
		fi
		sudo -v || return 1
		if ! command -v git >/dev/null 2>&1; then
			echo "git is not installed, installing git."
			bash -e -o pipefail -c '
				source "$1/dotfiles/.bash_aliases"
				apt_get update
				apt_get install -y git
			' bash "$PWD" || return 1
		fi
		;;
	*)
		printf 'Error: unsupported operating system: %s\n' "$os_name" >&2
		return 1
		;;
	esac

	# Only advance an untouched main checkout; local work always takes priority.
	# Apple's git launcher needs Command Line Tools before it can inspect a repo.
	if { [ "$os_name" != "Darwin" ] || xcode-select -p &>/dev/null; } &&
		command -v git >/dev/null 2>&1 &&
		branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null)" &&
		[ "$branch" = main ] &&
		worktree_status="$(git status --porcelain 2>/dev/null)" &&
		[ -z "$worktree_status" ]; then
		if GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND='ssh -o BatchMode=yes -o ConnectTimeout=10' git fetch origin main; then
			if git merge-base --is-ancestor HEAD FETCH_HEAD; then
				git merge --ff-only FETCH_HEAD || return 1
			else
				echo "Keeping local checkout: main has local commits."
			fi
		else
			echo "Warning: could not fetch from remote, continuing with local copy."
		fi
	else
		echo "Keeping local checkout: automatic updates require a clean main branch."
	fi

	case "$os_name" in
	Darwin) bash tools/setup_macos.sh ;;
	Linux) bash tools/setup_ubuntu.sh ;;
	esac
}

profile_setup_main() {
	local repo_dir
	repo_dir="$(cd -- "$(dirname -- "$1")" && pwd -P)" || return 1
	local state_home
	local log_dir
	local log_file
	local status_file
	local latest_link
	local timestamp
	local setup_status
	local tee_status
	local had_pipefail=0
	local output_tty=0
	local terminal_rows
	local terminal_size

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
	if [ -t 9 ]; then
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
			export PROFILE_SETUP_DEFER_PROGRESS_FINISH=1
		fi
		profile_setup_run "$repo_dir"
		setup_status=$?
		printf '%s\n' "$setup_status" >|"$status_file"
		exit "$setup_status"
	) 2>&1 | tee -a "$log_file"; then
		tee_status=0
	else
		tee_status=$?
	fi
	if [ "$output_tty" -eq 1 ]; then
		terminal_size="$(stty size <&9 2>/dev/null || true)"
		terminal_rows=${terminal_size%% *}
		case "$terminal_rows" in
		'' | *[!0-9]* | 0) printf '\033[r\n' >&9 || true ;;
		*) printf '\033[r\033[%d;1H\n' "$terminal_rows" >&9 || true ;;
		esac
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
	unset -f profile_setup_run profile_setup_main
	if [ "$setup_status" -ne 0 ]; then
		return "$setup_status"
	fi

	# Start the replacement login shell only after tee has closed the log.
	bash -l 9>&-
}

if [ -n "${ZSH_VERSION:-}" ]; then
	eval 'profile_setup_main "${(%):-%x}" 9>&1'
else
	profile_setup_main "${BASH_SOURCE[0]}" 9>&1
fi
