#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"

# shellcheck disable=SC1091
source "$repo_root/tools/common.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

first_step() {
	if [ "${PROFILE_SETUP_PROGRESS_FD:-}" = 9 ]; then
		if (: >&9) 2>/dev/null; then
			printf '%s\n' 'CHILD_FD9_LEAKED'
			return 11
		fi
		printf '%s\n' 'CHILD_FD9_CLOSED'
	fi
	printf '%s\n' 'FIRST_OUTPUT'
}

second_step() {
	printf '%s\n' 'SECOND_OUTPUT'
	return 7
}

fail_first() {
	return 9
}

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

export PATH="/usr/bin:/bin"
export PROFILE_SETUP_OUTPUT_TTY=1
export PROFILE_SETUP_PROGRESS_FD=9
export LC_ALL="C.UTF-8"
export TERM=xterm-256color
export LINES=24
export COLUMNS=80
export NO_COLOR=1

failed_functions=()
first_phase=(first_step)
second_phase=(second_step)
setup_progress_start "${first_phase[@]}" "${second_phase[@]}"
{
	run_functions "${first_phase[@]}"
	printf '%s\n' 'PARENT_HOOK'
	run_functions "${second_phase[@]}"
} >"$tmp/setup-output" 2>&1 9>"$tmp/ui-output"
setup_output="$(<"$tmp/setup-output")"
ui_output="$(<"$tmp/ui-output")"

assert_contains "$setup_output" "FIRST_OUTPUT"
assert_contains "$setup_output" "CHILD_FD9_CLOSED"
assert_not_contains "$setup_output" "CHILD_FD9_LEAKED"
assert_contains "$setup_output" "PARENT_HOOK"
assert_contains "$setup_output" "SECOND_OUTPUT"
assert_not_contains "$setup_output" "0% 0/2"
assert_not_contains "$setup_output" "━"
assert_not_contains "$setup_output" $'\033['
assert_contains "$ui_output" "0% 0/2 • first_step"
assert_contains "$ui_output" "50% 1/2 ✓ first_step"
assert_contains "$ui_output" "50% 1/2 • second_step"
assert_contains "$ui_output" "100% 2/2 ✗ second_step"
assert_contains "$ui_output" "$(tput csr 0 22)"
assert_contains "$ui_output" "$(tput cup 23 0)"
assert_contains "$ui_output" "$(tput csr 0 23)"
if [ "$(wc -l <"$tmp/ui-output")" -ne 1 ]; then
	printf '%s\n' 'FAIL: pinned progress emitted more than one terminal line'
	exit 1
fi
if [ "${failed_functions[*]}" != second_step ]; then
	printf 'FAIL: failed function tracking changed: %s\n' "${failed_functions[*]}"
	exit 1
fi

export PROFILE_SETUP_NO_LOGIN_SHELL=1
export PROFILE_DIR="$tmp"
set +e
exit_script >"$tmp/exit-output" 2>&1
setup_status=$?
set -e
if [ "$setup_status" -ne 1 ]; then
	printf 'FAIL: failed setup status was %s instead of 1\n' "$setup_status"
	exit 1
fi

export LINES=24
export COLUMNS=80
failed_functions=()
setup_progress_start first_step first_step
{
	run_function first_step
	export LINES=30
	export COLUMNS=40
	setup_progress_handle_resize
	setup_progress_finish
} >"$tmp/resize-output" 2>&1 9>"$tmp/resize-ui"
resize_ui="$(<"$tmp/resize-ui")"
assert_contains "$resize_ui" "$(LINES=24 tput csr 0 22)"
assert_contains "$resize_ui" "$(LINES=30 tput csr 0 28)"
assert_contains "$resize_ui" "$(LINES=30 tput cup 29 0)"
if [ "$SETUP_PROGRESS_PINNED" -ne 0 ]; then
	printf '%s\n' 'FAIL: progress footer remained pinned after finish'
	exit 1
fi

export LINES=24
export COLUMNS=80
export PROFILE_SETUP_PROGRESS_STATE_FILE="$tmp/progress-state"
failed_functions=()
setup_progress_start first_step
run_function first_step >"$tmp/managed-output" 2>&1 9>"$tmp/managed-ui"
if [ "$SETUP_PROGRESS_PINNED" -ne 1 ] ||
	[[ "$(<"$tmp/progress-state")" != *"100% 1/1 ✓ first_step"* ]] ||
	[[ "$(<"$tmp/managed-ui")" == *"$(tput csr 0 23)"* ]]; then
	printf '%s\n' 'FAIL: managed progress did not defer teardown until tee drained'
	exit 1
fi
unset PROFILE_SETUP_PROGRESS_STATE_FILE
# shellcheck disable=SC2034 # Consumed by the sourced progress renderer.
SETUP_PROGRESS_DEFER_FINISH=0
setup_progress_restore_terminal force 9>>"$tmp/managed-ui"
trap - WINCH

export PROFILE_SETUP_PROGRESS_STATE_FILE="$tmp/fatal-progress-state"
failed_functions=()
setup_progress_start first_step
setup_progress_begin first_step 9>"$tmp/fatal-managed-ui"
setup_progress_restore_terminal force 9>>"$tmp/fatal-managed-ui"
if [ -s "$PROFILE_SETUP_PROGRESS_STATE_FILE" ]; then
	printf '%s\n' 'FAIL: restored fatal progress retained a stale managed footer'
	exit 1
fi
unset PROFILE_SETUP_PROGRESS_STATE_FILE
trap - WINCH

export LINES=24
export COLUMNS=80
export PROFILE_SETUP_PROGRESS_STATE_FILE="$tmp/resized-progress-state"
failed_functions=()
setup_progress_start first_step first_step
setup_progress_begin first_step 9>"$tmp/resized-managed-ui"
if [ ! -s "$PROFILE_SETUP_PROGRESS_STATE_FILE" ]; then
	printf '%s\n' 'FAIL: managed progress did not record its initial footer'
	exit 1
fi
export COLUMNS=10
setup_progress_handle_resize 9>>"$tmp/resized-managed-ui"
if [ -s "$PROFILE_SETUP_PROGRESS_STATE_FILE" ]; then
	printf '%s\n' 'FAIL: narrow resize retained a stale managed footer'
	exit 1
fi
unset PROFILE_SETUP_PROGRESS_STATE_FILE

export LINES=10
export COLUMNS=24
failed_functions=()
setup_progress_start second_step
setup_progress_pin 9>"$tmp/narrow-ui"
# shellcheck disable=SC2034 # Consumed by the sourced progress renderer.
SETUP_PROGRESS_FAILED=1
setup_progress_build_line second_step OK
narrow_line="$SETUP_PROGRESS_LINE"
narrow_plain="$(printf '%s' "$narrow_line" | LC_ALL=C sed $'s/\033\\[[0-9;]*[A-Za-z]//g')"
setup_progress_restore_terminal 9>>"$tmp/narrow-ui"
trap - WINCH
if [ "${#narrow_plain}" -gt "$COLUMNS" ]; then
	printf 'FAIL: narrow progress is %d columns wide\n%s\n' "${#narrow_plain}" "$narrow_plain"
	exit 1
fi

export COLUMNS=10
export LC_ALL=C
failed_functions=()
setup_progress_start second_step
tiny_output="$(run_function second_step 9>"$tmp/tiny-ui" 2>&1)"
tiny_line="$(printf '%s\n' "$tiny_output" | tail -n 1)"
if [ "${#tiny_line}" -gt "$COLUMNS" ]; then
	printf 'FAIL: tiny ASCII failure progress is %d columns wide\n%s\n' \
		"${#tiny_line}" "$tiny_line"
	exit 1
fi

export COLUMNS=1
failed_functions=()
setup_progress_start first_step
one_column_output="$(run_function first_step 9>"$tmp/one-column-ui" 2>&1)"
one_column_line="$(printf '%s\n' "$one_column_output" | tail -n 1)"
if [ "${#one_column_line}" -gt "$COLUMNS" ]; then
	printf 'FAIL: one-column progress is %d columns wide\n%s\n' \
		"${#one_column_line}" "$one_column_line"
	exit 1
fi

unset NO_COLOR
export LINES=24
export COLUMNS=80
export LC_ALL="C.UTF-8"
failed_functions=()
setup_progress_start first_step
run_function first_step >"$tmp/colour-output" 2>&1 9>"$tmp/colour-ui"
colour_ui="$(<"$tmp/colour-ui")"
assert_contains "$colour_ui" $'\033[1;92m━'
assert_not_contains "$colour_ui" $'\033[38;2;'

unset PROFILE_SETUP_PROGRESS_FD
export PROFILE_SETUP_OUTPUT_TTY=0
export LC_ALL=C
failed_functions=()
setup_progress_start first_step
ascii_output="$(run_function first_step 2>&1)"
assert_contains "$ascii_output" "100% 1/1 OK first_step"
assert_contains "$ascii_output" "="
assert_not_contains "$ascii_output" "━"
assert_not_contains "$ascii_output" "✓"
assert_not_contains "$ascii_output" $'\033'

failed_functions=()
setup_progress_start fail_first first_step
aggregate_output="$(run_functions fail_first first_step 2>&1)"
assert_contains "$aggregate_output" "100% 2/2 FAIL first_step"

keepalive_tree="$tmp/keepalive-tree"
(
	SUDO_KEEPALIVE_PID=""
	# shellcheck disable=SC2329 # Invoked indirectly by keep_sudo_alive.
	sudo_command() {
		return 0
	}
	keep_sudo_alive
	keepalive_pid="$SUDO_KEEPALIVE_PID"
	sleep_pid=""
	for _ in {1..50}; do
		sleep_pid="$(ps -axo pid=,ppid=,comm= | awk -v parent="$keepalive_pid" \
			'$2 == parent && $3 ~ /sleep/ { found = $1 } END { if (found) print found }')"
		[ -n "$sleep_pid" ] && break
		sleep 0.02
	done
	if [ -z "$sleep_pid" ]; then
		printf '%s\n' 'FAIL: sudo keepalive sleep was not observable'
		exit 1
	fi
	if [ -x /usr/sbin/lsof ] && /usr/sbin/lsof -a -p "$sleep_pid" -d 9 2>/dev/null | grep -q .; then
		printf '%s\n' 'FAIL: sudo keepalive child inherited progress FD 9'
		exit 1
	fi
	stop_sudo_keepalive
	if kill -0 "$keepalive_pid" 2>/dev/null || kill -0 "$sleep_pid" 2>/dev/null; then
		printf '%s\n' 'FAIL: stopping sudo keepalive left a descendant running'
		exit 1
	fi
	printf '%s\n' 'KEEPALIVE_STOPPED' >"$keepalive_tree"
) 9>"$tmp/keepalive-fd9"
if [ "$(<"$keepalive_tree")" != KEEPALIVE_STOPPED ]; then
	printf '%s\n' 'FAIL: sudo keepalive lifecycle test did not complete'
	exit 1
fi

printf '%s\n' 'PASS: one progress footer persists while raw setup output remains intact'
