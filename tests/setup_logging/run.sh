#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"
entry="$repo_root/setup_entry.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"

printf '%s\n' \
	'#!/bin/bash' \
	'printf "sudo called\\n"' \
	'exit 0' >"$tmp/bin/sudo"
printf '%s\n' \
	'#!/bin/bash' \
	'printf "Darwin\\n"' >"$tmp/bin/uname"
printf '%s\n' \
	'#!/bin/bash' \
	'exit 1' >"$tmp/bin/xcode-select"
printf '%s\n' \
	'#!/bin/bash' \
	'printf "FAIL: git must not run\\n" >&2' \
	'exit 99' >"$tmp/bin/git"
# shellcheck disable=SC2016
printf '%s\n' \
	'#!/bin/bash' \
	'# shellcheck disable=SC1090' \
	'source "$PROFILE_TEST_COMMON"' \
	'fixture_step() {' \
	'  if [ "${PROFILE_SETUP_PROGRESS_FD:-}" = 9 ] && (: >&9) 2>/dev/null; then' \
	'    printf "FAIL: platform child inherited FD 9\\n" >&2' \
	'    return 97' \
	'  fi' \
	'  printf "platform stdout\\n"' \
	'  printf "platform stderr\\n" >&2' \
	'  return "${PROFILE_TEST_CHILD_STATUS:-0}"' \
	'}' \
	'failed_functions=()' \
	'setup_progress_start fixture_step' \
	'run_function fixture_step' \
	'if [ "${PROFILE_TEST_RESIZE_TAIL:-0}" = 1 ]; then' \
	'  stty rows 24 cols 24 <&9' \
	'  setup_progress_handle_resize' \
	'fi' \
	'exit "${PROFILE_TEST_CHILD_STATUS:-0}"' >"$tmp/platform-fixture"
# shellcheck disable=SC2016
printf '%s\n' \
	'#!/bin/bash' \
	'case "${1:-}" in' \
	'tools/setup_macos.sh)' \
	'	exec /bin/bash "$PROFILE_TEST_PLATFORM_FIXTURE"' \
	'	;;' \
	'-l)' \
	'	if (: >&9) 2>/dev/null; then' \
	'		printf "FAIL: login shell inherited FD 9\\n" >&2' \
	'		exit 97' \
	'	fi' \
	'	printf "LOGIN_SHELL_AFTER_LOG\\n"' \
	'	exit 0' \
	'	;;' \
	'esac' \
	'printf "FAIL: unexpected bash arguments: %s\\n" "$*" >&2' \
	'exit 98' >"$tmp/bin/bash"
chmod +x "$tmp/bin/"*
chmod +x "$tmp/platform-fixture"
export PROFILE_TEST_COMMON="$repo_root/tools/common.sh"
export PROFILE_TEST_PLATFORM_FIXTURE="$tmp/platform-fixture"

assert_contains() {
	local value="$1"
	local expected="$2"

	if [[ "$value" == *"$expected"* ]]; then
		return
	fi
	printf 'FAIL: expected output to contain %q\n%s\n' "$expected" "$value"
	exit 1
}

assert_not_contains() {
	local value="$1"
	local unexpected="$2"

	if [[ "$value" != *"$unexpected"* ]]; then
		return
	fi
	printf 'FAIL: expected output not to contain %q\n%s\n' "$unexpected" "$value"
	exit 1
}

file_mode() {
	stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1"
}

log_dir="$tmp/log dir"
source_output="$(
	PATH="$tmp/bin:$PATH" \
		PROFILE_SETUP_LOG_DIR="$log_dir" \
		PROFILE_TEST_CHILD_STATUS=0 \
		/bin/bash -c '
			set -e
			set -o pipefail
			before_pwd="$PWD"
			before_options="$-"
			before_pipefail="$(set -o | grep "^pipefail")"
			before_umask="$(umask)"
			trap ":" USR1
			before_trap="$(trap -p USR1)"
			exec 9>"$2"
			source "$1"
			source_status=$?
			printf "CALLER_FD9_OK\n" >&9
			exec 9>&-
			if [ "$PWD" = "$before_pwd" ] &&
				[ "$-" = "$before_options" ] &&
				[ "$(set -o | grep "^pipefail")" = "$before_pipefail" ] &&
				[ "$(umask)" = "$before_umask" ] &&
				[ "$(trap -p USR1)" = "$before_trap" ] &&
				! declare -F profile_setup_main >/dev/null &&
				! declare -F profile_setup_run >/dev/null; then
				printf "CALLER_STATE_OK\\n"
			fi
			printf "SOURCE_STATUS=%s\\n" "$source_status"
			printf "CALLER_AFTER\\n"
		' _ "$entry" "$tmp/caller-fd9" 2>&1
)"

assert_contains "$source_output" "platform stdout"
assert_contains "$source_output" "platform stderr"
assert_contains "$source_output" "LOGIN_SHELL_AFTER_LOG"
assert_contains "$source_output" "CALLER_STATE_OK"
assert_contains "$source_output" "SOURCE_STATUS=0"
assert_contains "$source_output" "CALLER_AFTER"
assert_not_contains "$source_output" "FAIL:"
if [ "$(<"$tmp/caller-fd9")" != CALLER_FD9_OK ]; then
	printf '%s\n' 'FAIL: sourced setup did not restore the caller FD 9'
	exit 1
fi

if [ "$(file_mode "$log_dir")" != 700 ]; then
	printf 'FAIL: log directory mode is %s\n' "$(file_mode "$log_dir")"
	exit 1
fi
if [ ! -L "$log_dir/latest.log" ]; then
	printf '%s\n' 'FAIL: latest.log is not a symlink'
	exit 1
fi
first_log="$log_dir/$(readlink "$log_dir/latest.log")"
if [ ! -f "$first_log" ] || [ "$(file_mode "$first_log")" != 600 ]; then
	printf '%s\n' 'FAIL: first log is absent or not mode 600'
	exit 1
fi
first_contents="$(<"$first_log")"
assert_contains "$first_contents" "platform stdout"
assert_contains "$first_contents" "platform stderr"
assert_not_contains "$first_contents" "LOGIN_SHELL_AFTER_LOG"
assert_not_contains "$first_contents" "CALLER_AFTER"
assert_not_contains "$first_contents" $'\033[1;23r'

if [ -x /bin/zsh ]; then
	zsh_log_dir="$tmp/zsh logs"
	zsh_output="$(
		PATH="$tmp/bin:$PATH" \
			PROFILE_SETUP_LOG_DIR="$zsh_log_dir" \
			PROFILE_TEST_CHILD_STATUS=0 \
			/bin/zsh -c '
				source "$1"
				printf "SOURCE_STATUS=%s\\n" "$?"
				printf "ZSH_CALLER_AFTER\\n"
			' _ "$entry" 2>&1
	)"
	assert_contains "$zsh_output" "SOURCE_STATUS=0"
	assert_contains "$zsh_output" "LOGIN_SHELL_AFTER_LOG"
	assert_contains "$zsh_output" "ZSH_CALLER_AFTER"
	zsh_log="$zsh_log_dir/$(readlink "$zsh_log_dir/latest.log")"
	zsh_contents="$(<"$zsh_log")"
	assert_not_contains "$zsh_contents" "LOGIN_SHELL_AFTER_LOG"
	assert_not_contains "$zsh_contents" "ZSH_CALLER_AFTER"
fi

failure_output="$(
	PATH="$tmp/bin:$PATH" \
		PROFILE_SETUP_LOG_DIR="$log_dir" \
		PROFILE_TEST_CHILD_STATUS=23 \
		/bin/bash -c '
			source "$1"
			printf "SOURCE_STATUS=%s\\n" "$?"
			printf "CALLER_AFTER_FAILURE\\n"
		' _ "$entry" 2>&1
)"
assert_contains "$failure_output" "SOURCE_STATUS=23"
assert_contains "$failure_output" "CALLER_AFTER_FAILURE"
assert_not_contains "$failure_output" "LOGIN_SHELL_AFTER_LOG"
second_log="$log_dir/$(readlink "$log_dir/latest.log")"
if [ "$second_log" = "$first_log" ] || [ ! -f "$first_log" ] || [ ! -f "$second_log" ]; then
	printf '%s\n' 'FAIL: latest.log did not advance while retaining the first log'
	exit 1
fi

errexit_log_dir="$tmp/errexit logs"
set +e
errexit_output="$(
	PATH="$tmp/bin:$PATH" \
		PROFILE_SETUP_LOG_DIR="$errexit_log_dir" \
		PROFILE_TEST_CHILD_STATUS=23 \
		/bin/bash -e -o pipefail -c 'source "$1"' _ "$entry" 2>&1
)"
errexit_status=$?
set -e
if [ "$errexit_status" -ne 23 ]; then
	printf 'FAIL: source under errexit returned %s instead of 23\n%s\n' "$errexit_status" "$errexit_output"
	exit 1
fi
assert_contains "$errexit_output" "platform stderr"
assert_not_contains "$errexit_output" "LOGIN_SHELL_AFTER_LOG"
assert_not_contains "$errexit_output" "could not finish writing setup log"

noclobber_log_dir="$tmp/noclobber logs"
noclobber_output="$(
	PATH="$tmp/bin:$PATH" \
		PROFILE_SETUP_LOG_DIR="$noclobber_log_dir" \
		PROFILE_TEST_CHILD_STATUS=0 \
		/bin/bash -C -c '
			source "$1"
			printf "SOURCE_STATUS=%s\n" "$?"
			case $- in
			*C*) printf "NOCLOBBER_RESTORED\n" ;;
			esac
		' _ "$entry" 2>&1
)"
assert_contains "$noclobber_output" "SOURCE_STATUS=0"
assert_contains "$noclobber_output" "NOCLOBBER_RESTORED"
assert_not_contains "$noclobber_output" "FAIL:"

execute_log_dir="$tmp/executed logs"
set +e
execute_output="$(
	PATH="$tmp/bin:$PATH" \
		PROFILE_SETUP_LOG_DIR="$execute_log_dir" \
		PROFILE_TEST_CHILD_STATUS=0 \
		/bin/bash "$entry" 2>&1
)"
execute_status=$?
set -e
if [ "$execute_status" -ne 0 ]; then
	printf 'FAIL: executed entry point returned %s\n%s\n' "$execute_status" "$execute_output"
	exit 1
fi
assert_contains "$execute_output" "platform stdout"
assert_contains "$execute_output" "platform stderr"
assert_contains "$execute_output" "LOGIN_SHELL_AFTER_LOG"
execute_log="$execute_log_dir/$(readlink "$execute_log_dir/latest.log")"
execute_contents="$(<"$execute_log")"
assert_not_contains "$execute_contents" "LOGIN_SHELL_AFTER_LOG"

blocked_log_dir="$tmp/blocked logs"
mkdir -p "$blocked_log_dir/latest.log"
blocked_output="$(
	PATH="$tmp/bin:$PATH" \
		PROFILE_SETUP_LOG_DIR="$blocked_log_dir" \
		PROFILE_TEST_CHILD_STATUS=0 \
		/bin/bash -c '
			source "$1"
			printf "SOURCE_STATUS=%s\\n" "$?"
		' _ "$entry" 2>&1
)"
assert_contains "$blocked_output" "latest setup log path is a directory"
assert_contains "$blocked_output" "SOURCE_STATUS=1"
assert_not_contains "$blocked_output" "platform stdout"
assert_not_contains "$blocked_output" "LOGIN_SHELL_AFTER_LOG"
if [ ! -d "$blocked_log_dir/latest.log" ]; then
	printf '%s\n' 'FAIL: existing latest.log directory was modified'
	exit 1
fi
if find "$blocked_log_dir" -name 'setup-*' -print -quit | grep -q .; then
	printf '%s\n' 'FAIL: blocked log directory contains an orphan run log'
	exit 1
fi

linked_log_dir="$tmp/linked logs"
mkdir -p "$linked_log_dir/archive"
ln -s archive "$linked_log_dir/latest.log"
linked_output="$(
	PATH="$tmp/bin:$PATH" \
		PROFILE_SETUP_LOG_DIR="$linked_log_dir" \
		PROFILE_TEST_CHILD_STATUS=0 \
		/bin/bash -c '
			source "$1"
			printf "SOURCE_STATUS=%s\\n" "$?"
		' _ "$entry" 2>&1
)"
assert_contains "$linked_output" "latest setup log path is a directory"
assert_contains "$linked_output" "SOURCE_STATUS=1"
if [ ! -L "$linked_log_dir/latest.log" ] ||
	[ "$(readlink "$linked_log_dir/latest.log")" != archive ] ||
	find "$linked_log_dir/archive" -mindepth 1 -print -quit | grep -q .; then
	printf '%s\n' 'FAIL: symlinked latest.log directory was modified'
	exit 1
fi

if [ "$(/usr/bin/uname)" = Darwin ]; then
	pty_log_dir="$tmp/pty logs"
	pty_transcript="$tmp/pty-transcript"
	set +e
	/usr/bin/script -q "$pty_transcript" /usr/bin/env \
		"PATH=$tmp/bin:$PATH" \
		"PROFILE_SETUP_LOG_DIR=$pty_log_dir" \
		PROFILE_TEST_CHILD_STATUS=0 \
		PROFILE_TEST_RESIZE_TAIL=1 \
		PROFILE_TEST_COMMON="$PROFILE_TEST_COMMON" \
		PROFILE_TEST_PLATFORM_FIXTURE="$PROFILE_TEST_PLATFORM_FIXTURE" \
		TERM=xterm-256color LINES=24 COLUMNS=80 NO_COLOR=1 \
		/bin/bash "$entry" >"$tmp/pty-stdout" 2>&1
	pty_status=$?
	set -e
	if [ "$pty_status" -ne 0 ]; then
		printf 'FAIL: PTY entry point returned %s\n%s\n' "$pty_status" "$(<"$tmp/pty-stdout")"
		exit 1
	fi
	pty_contents="$(<"$pty_transcript")"
	assert_contains "$pty_contents" $'\033[1;23r'
	assert_contains "$pty_contents" "platform stdout"
	assert_contains "$pty_contents" "100% 1/1 ✓"
	assert_contains "$pty_contents" "LOGIN_SHELL_AFTER_LOG"
	assert_not_contains "$pty_contents" "FAIL:"
	log_saved_offset="$(LC_ALL=C grep -abo 'Setup log saved to:' "$pty_transcript" |
		awk -F: '{ offset = $1 } END { print offset }')"
	final_bar_offset="$(LC_ALL=C grep -abo '100% 1/1' "$pty_transcript" |
		awk -F: '{ offset = $1 } END { print offset }')"
	if [ -z "$log_saved_offset" ] || [ -z "$final_bar_offset" ] ||
		[ "$final_bar_offset" -le "$log_saved_offset" ]; then
		printf '%s\n' 'FAIL: final footer was not rendered after the log-save message'
		exit 1
	fi
	pty_log="$pty_log_dir/$(readlink "$pty_log_dir/latest.log")"
	pty_log_contents="$(<"$pty_log")"
	assert_contains "$pty_log_contents" "platform stdout"
	assert_not_contains "$pty_log_contents" $'\033[1;23r'
	assert_not_contains "$pty_log_contents" "100% 1/1 ✓"
	if LC_ALL=C grep -Eq $'\033\\[[0-9;]*r' "$pty_log"; then
		printf '%s\n' 'FAIL: raw setup log contains terminal scroll-region controls'
		exit 1
	fi
	if find "$pty_log_dir" \( -name '.setup-status.*' -o -name '.setup-progress.*' \) \
		-print -quit | grep -q .; then
		printf '%s\n' 'FAIL: PTY setup left private state files behind'
		exit 1
	fi
fi

printf '%s\n' 'PASS: setup logs are private, complete, discoverable, and bounded'
