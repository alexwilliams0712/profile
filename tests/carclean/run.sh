#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"
aliases="$repo_root/dotfiles/.bash_aliases"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin" "$tmp/work/alpha crate" "$tmp/work/bravo" "$tmp/work/not-rust"
touch "$tmp/work/alpha crate/Cargo.toml" "$tmp/work/bravo/Cargo.toml"

cat >"$tmp/bin/cargo" <<'EOF'
#!/usr/bin/env bash
[ "$1" = clean ] || exit 2
case "${PWD##*/}" in
"alpha crate") printf '     Removed 12 files, 1.2MiB total\n' >&2 ;;
bravo) printf '     Removed 0 files\n' >&2 ;;
*) exit 3 ;;
esac
EOF
chmod +x "$tmp/bin/cargo"

# shellcheck source=/dev/null
source "$aliases"

export PATH="$tmp/bin:$PATH"
start_dir="$tmp/work"
cd "$start_dir" || exit 1

output=$(carclean)
status=$?

if [ "$status" -ne 0 ]; then
	printf 'FAIL: carclean returned %s\n' "$status"
	exit 1
fi

if [ "$PWD" != "$start_dir" ]; then
	printf 'FAIL: carclean changed directory to %s\n' "$PWD"
	exit 1
fi

if [[ "$output" != *'| alpha crate | 1.2MiB'* ]]; then
	printf 'FAIL: missing cleaned amount for alpha crate\n%s\n' "$output"
	exit 1
fi

if [[ "$output" != *'| bravo       | 0 B'* ]]; then
	printf 'FAIL: missing zero cleaned amount for bravo\n%s\n' "$output"
	exit 1
fi

if [[ "$output" == *not-rust* ]]; then
	printf 'FAIL: non-Rust directory appeared in output\n%s\n' "$output"
	exit 1
fi

printf 'PASS: carclean cleaned immediate Rust subdirectories and summarised the results\n'
