#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"
ubuntu_setup="$repo_root/tools/setup_ubuntu.sh"

# shellcheck disable=SC1091
source "$repo_root/tools/common.sh"

fail() {
	printf 'FAIL: %s\n' "$1"
	exit 1
}

unset SSH_CONNECTION SSH_CLIENT SSH_TTY
if profile_is_running_over_ssh; then
	fail 'a local session was mistaken for SSH'
fi
for ssh_variable in SSH_CONNECTION SSH_CLIENT SSH_TTY; do
	printf -v "$ssh_variable" '%s' fixture
	if ! profile_is_running_over_ssh; then
		fail "$ssh_variable did not identify an SSH session"
	fi
	unset "$ssh_variable"
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
function_fixture="$tmp/ubuntu-functions.sh"
for function_name in \
	tailscale_apt_package_is_installed \
	tailscale_apt_upgrade_is_held \
	run_apt_upgrader \
	install_tailscale; do
	sed -n "/^${function_name}() {$/,/^}$/p" "$ubuntu_setup" >>"$function_fixture"
done
# shellcheck disable=SC1090 # Functions are extracted without running setup.
source "$function_fixture"

apt-mark() {
	printf '%s\n' "${PROFILE_TEST_HELD_PACKAGES:-}"
}
PROFILE_TEST_HELD_PACKAGES=tailscale-archive-keyring
if tailscale_apt_upgrade_is_held; then
	fail 'the archive keyring was mistaken for a held Tailscale package'
fi
PROFILE_TEST_HELD_PACKAGES=tailscale
if ! tailscale_apt_upgrade_is_held; then
	fail 'an exact Tailscale apt hold was not recognised'
fi

mkdir -p "$tmp/bin"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$tmp/bin/tailscale"
chmod +x "$tmp/bin/tailscale"
export PATH="$tmp/bin:/usr/bin:/bin"
events="$tmp/events"

log() {
	:
}

sudo() {
	printf 'sudo %s\n' "$*" >>"$events"
	case "$*" in
	'apt-mark hold tailscale') return "${PROFILE_TEST_HOLD_STATUS:-0}" ;;
	'apt-mark unhold tailscale') return "${PROFILE_TEST_UNHOLD_STATUS:-0}" ;;
	esac
	return 0
}

apt_upgrader() {
	printf '%s\n' apt-upgrader >>"$events"
	return "${PROFILE_TEST_UPGRADER_STATUS:-0}"
}

profile_is_running_over_ssh() {
	[ "${PROFILE_TEST_REMOTE:-0}" = 1 ]
}

tailscale_apt_package_is_installed() {
	[ "${PROFILE_TEST_APT_INSTALLED:-0}" = 1 ]
}

tailscale_apt_upgrade_is_held() {
	[ "${PROFILE_TEST_APT_HELD:-0}" = 1 ]
}

export PROFILE_TEST_REMOTE=1
export PROFILE_TEST_APT_INSTALLED=1
export PROFILE_TEST_APT_HELD=0
export PROFILE_TEST_HOLD_STATUS=0
export PROFILE_TEST_UNHOLD_STATUS=0
export PROFILE_TEST_UPGRADER_STATUS=0
: >"$events"
run_apt_upgrader
if [ "$(tr '\n' '|' <"$events")" != \
	'sudo apt-mark hold tailscale|apt-upgrader|sudo apt-mark unhold tailscale|' ]; then
	fail 'an SSH apt upgrade did not protect installed Tailscale'
fi

export PROFILE_TEST_UPGRADER_STATUS=17
: >"$events"
set +e
run_apt_upgrader
upgrade_status=$?
set -e
if [ "$upgrade_status" -ne 17 ] ||
	[ "$(tail -n 1 "$events")" != 'sudo apt-mark unhold tailscale' ]; then
	fail 'a failed apt upgrade did not restore the temporary hold and status'
fi

export PROFILE_TEST_UPGRADER_STATUS=0
export PROFILE_TEST_UNHOLD_STATUS=19
: >"$events"
set +e
run_apt_upgrader
unhold_status=$?
set -e
if [ "$unhold_status" -ne 19 ]; then
	fail 'a failed restoration of the temporary apt hold was not reported'
fi

export PROFILE_TEST_UNHOLD_STATUS=0
export PROFILE_TEST_HOLD_STATUS=9
: >"$events"
set +e
run_apt_upgrader
hold_status=$?
set -e
if [ "$hold_status" -eq 0 ] || [ "$(<"$events")" != 'sudo apt-mark hold tailscale' ]; then
	fail 'a failed apt hold still ran upgrades or changed the prior hold state'
fi

export PROFILE_TEST_HOLD_STATUS=0
export PROFILE_TEST_APT_HELD=1
: >"$events"
run_apt_upgrader
if [ "$(<"$events")" != apt-upgrader ]; then
	fail 'a pre-existing Tailscale hold was modified'
fi

export PROFILE_TEST_APT_HELD=0
export PROFILE_TEST_REMOTE=0
: >"$events"
run_apt_upgrader
if [ "$(<"$events")" != apt-upgrader ]; then
	fail 'a local apt upgrade unnecessarily held Tailscale'
fi

export PROFILE_TEST_REMOTE=1
export PROFILE_TEST_APT_INSTALLED=0
: >"$events"
run_apt_upgrader
if [ "$(<"$events")" != apt-upgrader ]; then
	fail 'an absent Tailscale package was unnecessarily held'
fi

print_function_name() {
	:
}

curl() {
	printf '%s\n' installer >>"$events"
}

sh() {
	while IFS= read -r _; do :; done
}

export PROFILE_TEST_REMOTE=1
: >"$events"
install_tailscale
if [ -s "$events" ]; then
	fail 'Tailscale setup changed the system over SSH'
fi

export PROFILE_TEST_REMOTE=0
: >"$events"
install_tailscale
if [ "$(tr '\n' '|' <"$events")" != \
	'installer|sudo tailscale up --ssh --stateful-filtering|sudo ufw deny ssh|' ]; then
	fail 'local Tailscale installation and configuration changed'
fi

if ! grep -Fq 'declare -F run_apt_upgrader' "$repo_root/tools/common.sh"; then
	fail 'the shared pyenv prerequisites bypass the protected apt upgrader'
fi
if [ "$(grep -Ec '^[[:space:]]+run_apt_upgrader$' "$ubuntu_setup")" -ne 6 ]; then
	fail 'a normal Ubuntu setup apt upgrade bypasses the SSH protection'
fi
if grep -REq 'TAILSCALE_UPGRADE_REQUESTED|collect_tailscale_upgrade_preference' \
	"$repo_root/tools"; then
	fail 'the old Tailscale upgrade prompt remains in setup'
fi

printf '%s\n' 'PASS: Tailscale changes are skipped over SSH'
