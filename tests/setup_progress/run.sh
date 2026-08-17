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

export NO_COLOR=1
export PATH="/usr/bin:/bin"
export PROFILE_SETUP_OUTPUT_TTY=1
export LC_ALL="C.UTF-8"
failed_functions=()
first_phase=(first_step)
second_phase=(second_step)
setup_progress_start "${first_phase[@]}" "${second_phase[@]}"
output_file="$tmp/progress-output"
{
	run_functions "${first_phase[@]}"
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
