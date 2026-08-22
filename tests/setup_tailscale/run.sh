#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"
ubuntu_setup="$repo_root/tools/setup_ubuntu.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
sed -n '/^install_tailscale() {$/,/^}$/p' "$ubuntu_setup" >"$tmp/install-tailscale.sh"
# shellcheck disable=SC1091 # Function is extracted without running setup.
source "$tmp/install-tailscale.sh"

mkdir -p "$tmp/bin"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$tmp/bin/tailscale"
chmod +x "$tmp/bin/tailscale"
export PATH="$tmp/bin:/usr/bin:/bin"
events="$tmp/events"

print_function_name() {
	:
}

log() {
	:
}

curl() {
	printf '%s\n' installer >>"$events"
}

sh() {
	while IFS= read -r _; do :; done
}

sudo() {
	printf 'sudo %s\n' "$*" >>"$events"
}

unset SSH_CONNECTION SSH_CLIENT SSH_TTY
for ssh_variable in SSH_CONNECTION SSH_CLIENT SSH_TTY; do
	printf -v "$ssh_variable" '%s' fixture
	: >"$events"
	install_tailscale
	if [ -s "$events" ]; then
		printf 'FAIL: Tailscale installation ran with %s set\n' "$ssh_variable"
		exit 1
	fi
	unset "$ssh_variable"
done

: >"$events"
install_tailscale
if [ "$(tr '\n' '|' <"$events")" != \
	'installer|sudo tailscale up --ssh --stateful-filtering|sudo ufw deny ssh|' ]; then
	printf '%s\n' 'FAIL: local Tailscale installation changed'
	exit 1
fi

printf '%s\n' 'PASS: Tailscale installation is skipped over SSH'
