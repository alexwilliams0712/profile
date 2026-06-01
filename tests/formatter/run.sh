#!/usr/bin/env bash
# Self-contained test for formatter_json: proves comments are preserved on both
# .json and .json5, keys are sorted, colons aligned, and json5 normalises to
# strict JSON. Copies fixtures to a temp dir so the committed inputs are never
# reformatted in place. Exits non-zero on any mismatch.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"
aliases="$repo_root/dotfiles/.bash_aliases"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cp "$here/input.json" "$here/input.json5" "$tmp/"

# shellcheck source=/dev/null
source "$aliases"

(
	cd "$tmp" || exit 1
	formatter_json
)

status=0
for ext in json json5; do
	if diff -u "$here/expected.$ext" "$tmp/input.$ext"; then
		echo "PASS: input.$ext formatted as expected (comments preserved)"
	else
		echo "FAIL: input.$ext did not match expected.$ext"
		status=1
	fi
done

if diff -q "$tmp/input.json" "$tmp/input.json5" >/dev/null; then
	echo "PASS: .json and .json5 produce byte-identical output"
else
	echo "FAIL: .json and .json5 output differ"
	status=1
fi

exit "$status"
