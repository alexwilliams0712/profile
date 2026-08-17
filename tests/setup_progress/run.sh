#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"

# shellcheck disable=SC1091
source "$repo_root/tools/common.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

first_step() {
	:
}

second_step() {
	return 7
}

fail_first() {
	return 9
}

export NO_COLOR=1
export PATH="/usr/bin:/bin"
export PROFILE_SETUP_OUTPUT_TTY=1
export LC_ALL="C.UTF-8"
export TERM=xterm-256color
export COLUMNS=80
failed_functions=()
first_phase=(first_step)
second_phase=(second_step)
setup_progress_start "${first_phase[@]}" "${second_phase[@]}"
output_file="$tmp/progress-output"
{
	run_functions "${first_phase[@]}"
	setup_progress_clear
	printf '%s\n' 'PARENT_HOOK'
	run_functions "${second_phase[@]}"
} >"$output_file" 2>&1
output="$(<"$output_file")"

if [[ "$output" != *"50% 1/2 ✓ first_step"* ]]; then
	printf 'FAIL: first progress update is missing\n%s\n' "$output"
	exit 1
fi
if [[ "$output" != *"100% 2/2 ✗ second_step"* ]]; then
	printf 'FAIL: final progress update is missing\n%s\n' "$output"
	exit 1
fi
final_progress="$(printf '%s\n' "$output" | grep '100% 2/2')"
if [[ "$final_progress" == *"╺"* ]]; then
	printf 'FAIL: completed progress bar still has a continuation marker\n%s\n' "$final_progress"
	exit 1
fi
if [[ "$output" != *"━"* ]]; then
	printf 'FAIL: Rich-style progress bar is missing\n%s\n' "$output"
	exit 1
fi
if [[ "$output" != *"50% 1/2 ✓ first_step"$'\r\033[2K'"PARENT_HOOK"* ]]; then
	printf 'FAIL: incomplete progress did not redraw in place\n%s\n' "$output"
	exit 1
fi
if [[ "$output" != *"first_step"*"PARENT_HOOK"*"second_step"* ]]; then
	printf 'FAIL: phased execution order changed\n%s\n' "$output"
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

failed_functions=()
setup_progress_start first_step first_step
adjacent_output="$(run_functions first_step first_step 2>&1)"
if [[ "$adjacent_output" != *"50% 1/2 ✓ first_step"$'\r\033[2K'">>> first_step"* ]]; then
	printf 'FAIL: adjacent function did not clear the live bar\n%s\n' "$adjacent_output"
	exit 1
fi

failed_functions=()
setup_progress_start fail_first first_step
aggregate_output="$(run_functions fail_first first_step 2>&1)"
if [[ "$aggregate_output" != *"100% 2/2 ✗ first_step"* ]]; then
	printf 'FAIL: final progress lost an earlier failure\n%s\n' "$aggregate_output"
	exit 1
fi

export COLUMNS=24
failed_functions=()
setup_progress_start first_step
narrow_output="$(run_function first_step 2>&1)"
narrow_line="$(printf '%s\n' "$narrow_output" | tail -n 1 | LC_ALL=C sed $'s/\033\\[[0-9;]*[A-Za-z]//g; s/\r//g')"
if [ "${#narrow_line}" -gt "$COLUMNS" ]; then
	printf 'FAIL: narrow-terminal progress is %d columns wide\n%s\n' "${#narrow_line}" "$narrow_line"
	exit 1
fi

export LC_ALL=C
failed_functions=()
setup_progress_start second_step
narrow_ascii_output="$(run_function second_step 2>&1)"
narrow_ascii_line="$(printf '%s\n' "$narrow_ascii_output" | tail -n 1 | LC_ALL=C sed $'s/\033\\[[0-9;]*[A-Za-z]//g; s/\r//g')"
if [ "${#narrow_ascii_line}" -gt "$COLUMNS" ]; then
	printf 'FAIL: narrow ASCII failure progress is %d columns wide\n%s\n' \
		"${#narrow_ascii_line}" "$narrow_ascii_line"
	exit 1
fi
export COLUMNS=80
export LC_ALL="C.UTF-8"

unset NO_COLOR
failed_functions=()
setup_progress_start first_step
colour_output="$(run_function first_step 2>&1)"
if [[ "$colour_output" != *$'\033[1;92m'"━"* ]] ||
	[[ "$colour_output" == *$'\033[38;2;'* ]]; then
	printf 'FAIL: interactive progress is not Rich-style bright green\n%s\n' "$colour_output"
	exit 1
fi

export PROFILE_SETUP_OUTPUT_TTY=0
export LC_ALL=C
failed_functions=()
setup_progress_start first_step
ascii_output="$(run_function first_step 2>&1)"
if [[ "$ascii_output" != *"100% 1/1 OK first_step"* ]] ||
	[[ "$ascii_output" != *"="* ]] ||
	[[ "$ascii_output" == *"━"* ]] ||
	[[ "$ascii_output" == *"✓"* ]] ||
	[[ "$ascii_output" == *$'\033'* ]]; then
	printf 'FAIL: non-interactive progress fallback is unstable\n%s\n' "$ascii_output"
	exit 1
fi

printf '%s\n' 'PASS: progress plans, phases, failures, and rendering work'
