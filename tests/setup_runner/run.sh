#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"

# shellcheck disable=SC1091
source "$repo_root/tools/common.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

first_step() {
	printf '%s\n' first >>"$tmp/order"
}

failed_step() {
	printf '%s\n' failed >>"$tmp/order"
	return 7
}

last_step() {
	printf '%s\n' last >>"$tmp/order"
}

failed_functions=()
run_functions first_step failed_step last_step >"$tmp/runner-output" 2>&1
if [ "$(tr '\n' ' ' <"$tmp/order")" != 'first failed last ' ] ||
	[ "${failed_functions[*]}" != failed_step ]; then
	printf '%s\n' 'FAIL: setup runner did not continue and aggregate failures'
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

keepalive_pids="$tmp/keepalive-pids"
set +e
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
	printf '%s %s\n' "$keepalive_pid" "$sleep_pid" >"$keepalive_pids"
	exit 7
)
keepalive_status=$?
set -e
read -r keepalive_pid sleep_pid <"$keepalive_pids"
if [ "$keepalive_status" -ne 7 ]; then
	printf 'FAIL: keepalive EXIT path changed status to %s\n' "$keepalive_status"
	exit 1
fi
if kill -0 "$keepalive_pid" 2>/dev/null || kill -0 "$sleep_pid" 2>/dev/null; then
	printf '%s\n' 'FAIL: keepalive EXIT path left a descendant running'
	exit 1
fi

printf '%s\n' 'PASS: setup runner continues, reports failures, and reaps sudo keepalive'
