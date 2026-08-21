#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"
ubuntu_setup="$repo_root/tools/setup_ubuntu.sh"
macos_setup="$repo_root/tools/setup_macos.sh"

# shellcheck disable=SC1091
source "$repo_root/tools/common.sh"

fail() {
	printf 'FAIL: %s\n' "$1"
	exit 1
}

# shellcheck disable=SC2329 # Invoked indirectly by the preference collector.
tailscale_is_installed() {
	return 1
}
TAILSCALE_UPGRADE_REQUESTED=true
exec 3<<<"unread input"
collect_tailscale_upgrade_preference <&3
IFS= read -r remaining_input <&3
exec 3<&-
if [ "$TAILSCALE_UPGRADE_REQUESTED" != false ] || [ "$remaining_input" != 'unread input' ]; then
	fail 'an absent Tailscale installation prompted for an upgrade'
fi

# shellcheck disable=SC2329 # Invoked indirectly by the preference collector.
tailscale_is_installed() {
	return 0
}
TAILSCALE_UPGRADE_REQUESTED=true
collect_tailscale_upgrade_preference </dev/null
if [ "$TAILSCALE_UPGRADE_REQUESTED" != false ]; then
	fail 'EOF did not default the Tailscale upgrade choice to no'
fi
collect_tailscale_upgrade_preference <<<"YES"
if [ "$TAILSCALE_UPGRADE_REQUESTED" != true ]; then
	fail 'an explicit Tailscale upgrade was not accepted'
fi
collect_tailscale_upgrade_preference <<<"no"
if [ "$TAILSCALE_UPGRADE_REQUESTED" != false ]; then
	fail 'a declined Tailscale upgrade was accepted'
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
function_fixture="$tmp/ubuntu-functions.sh"
for function_name in \
	tailscale_apt_package_is_installed \
	tailscale_apt_upgrade_is_held \
	run_apt_upgrader \
	upgrade_tailscale \
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

tailscale_upgrade_is_declined() {
	[ "${PROFILE_TEST_UPGRADE_DECLINED:-0}" = 1 ]
}

tailscale_apt_package_is_installed() {
	[ "${PROFILE_TEST_APT_INSTALLED:-0}" = 1 ]
}

tailscale_apt_upgrade_is_held() {
	[ "${PROFILE_TEST_APT_HELD:-0}" = 1 ]
}

export PROFILE_TEST_UPGRADE_DECLINED=1
export PROFILE_TEST_APT_INSTALLED=1
export PROFILE_TEST_APT_HELD=0
export PROFILE_TEST_HOLD_STATUS=0
export PROFILE_TEST_UNHOLD_STATUS=0
export PROFILE_TEST_UPGRADER_STATUS=0
: >"$events"
run_apt_upgrader
if [ "$(tr '\n' '|' <"$events")" != \
	'sudo apt-mark hold tailscale|apt-upgrader|sudo apt-mark unhold tailscale|' ]; then
	fail 'a declined upgrade was not protected by a temporary apt hold'
fi

export PROFILE_TEST_UPGRADER_STATUS=17
: >"$events"
set +e
run_apt_upgrader
upgrade_status=$?
set -e
if [ "$upgrade_status" -ne 17 ] ||
	[ "$(tail -n 1 "$events")" != 'sudo apt-mark unhold tailscale' ]; then
	fail 'a failed apt upgrade did not restore the temporary hold and its status'
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
export PROFILE_TEST_UPGRADE_DECLINED=0
: >"$events"
run_apt_upgrader
if [ "$(<"$events")" != apt-upgrader ]; then
	fail 'an approved Tailscale upgrade was held back'
fi

export PROFILE_TEST_UPGRADE_DECLINED=1
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
	return "${PROFILE_TEST_INSTALLER_STATUS:-0}"
}

sh() {
	while IFS= read -r _; do :; done
}

tailscale_is_installed() {
	[ "${PROFILE_TEST_TAILSCALE_INSTALLED:-0}" = 1 ]
}

export PROFILE_TEST_TAILSCALE_INSTALLED=0
export PROFILE_TEST_INSTALLER_STATUS=0
TAILSCALE_UPGRADE_REQUESTED=false
: >"$events"
install_tailscale
if [ "$(grep -c '^installer$' "$events")" -ne 1 ]; then
	fail 'an absent Tailscale installation was not installed exactly once'
fi

export PROFILE_TEST_TAILSCALE_INSTALLED=1
TAILSCALE_UPGRADE_REQUESTED=false
: >"$events"
install_tailscale
if grep -q '^installer$' "$events"; then
	fail 'an installed Tailscale package ran its installer after a declined upgrade'
fi
if [ "$(tr '\n' '|' <"$events")" != \
	'sudo tailscale up --ssh --stateful-filtering|sudo ufw deny ssh|' ]; then
	fail 'a skipped installer no longer applied the existing Tailscale configuration'
fi

TAILSCALE_UPGRADE_REQUESTED=true
: >"$events"
install_tailscale
if [ "$(grep -c '^installer$' "$events")" -ne 1 ]; then
	fail 'an approved Tailscale upgrade did not run its installer exactly once'
fi

export PROFILE_TEST_APT_HELD=1
: >"$events"
install_tailscale
if [ "$(tr '\n' '|' <"$events")" != \
	'sudo apt-mark unhold tailscale|installer|sudo apt-mark hold tailscale|sudo tailscale up --ssh --stateful-filtering|sudo ufw deny ssh|' ]; then
	fail 'an approved upgrade did not restore the existing Tailscale apt hold'
fi

export PROFILE_TEST_INSTALLER_STATUS=29
: >"$events"
set +e
install_tailscale
installer_status=$?
set -e
if [ "$installer_status" -ne 29 ] ||
	[ "$(tail -n 1 "$events")" != 'sudo apt-mark hold tailscale' ]; then
	fail 'a failed approved upgrade did not restore the apt hold and installer status'
fi

for setup in "$macos_setup" "$ubuntu_setup"; do
	prompt_line="$(awk '/^main\(\) \{/ { in_main = 1 } in_main && /collect_tailscale_upgrade_preference/ { print NR; exit }' \
		"$setup")"
	first_step_line="$(awk '/^main\(\) \{/ { in_main = 1 } in_main && /run_functions|keep_sudo_alive/ { print NR; exit }' \
		"$setup")"
	if [ -z "$prompt_line" ] || [ -z "$first_step_line" ] || [ "$prompt_line" -ge "$first_step_line" ]; then
		fail "$setup does not collect the Tailscale upgrade choice before setup actions"
	fi
done

if ! grep -Fq 'declare -F run_apt_upgrader' "$repo_root/tools/common.sh"; then
	fail 'the shared pyenv prerequisites bypass the protected apt upgrader'
fi
if [ "$(grep -Ec '^[[:space:]]+run_apt_upgrader$' "$ubuntu_setup")" -ne 6 ]; then
	fail 'a normal Ubuntu setup apt upgrade bypasses the Tailscale protection'
fi

printf '%s\n' 'PASS: Tailscale installs and upgrades are explicit and SSH-safe by default'
