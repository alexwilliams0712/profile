#!/usr/bin/env bash
# Self-contained test for formatter: proves it reports only files it changed,
# and that JSON comments are preserved on both .json and .json5, keys are
# sorted, colons aligned, and json5 normalises to strict JSON. Copies fixtures
# to a temp dir so the committed inputs are never reformatted in place.
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"
aliases="$repo_root/dotfiles/.bash_aliases"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cp "$here/input.json" "$here/input.json5" "$tmp/"
unusable_tmp="$tmp/not-a-directory"
: >"$unusable_tmp"

# shellcheck source=/dev/null
source "$aliases"

first_output="$({
	cd "$tmp" || exit 1
	TMPDIR="$unusable_tmp" formatter
} 2>&1)"

status=0
line_count="$(printf '%s\n' "$first_output" | grep -c .)"
if [ "$line_count" -eq 2 ]; then
	echo "PASS: formatter reported exactly two modified files"
else
	echo "FAIL: formatter produced $line_count lines; expected exactly two:"
	printf '%s\n' "$first_output"
	status=1
fi

unexpected_output="$(printf '%s\n' "$first_output" | grep -Ev '^[0-9]{4}-[0-9]{2}-[0-9]{2} .* - (\./)?input\.(json|json5)$' || true)"
if [ -n "$unexpected_output" ]; then
	echo "FAIL: formatter produced unexpected output:"
	printf '%s\n' "$unexpected_output"
	status=1
else
	echo "PASS: formatter does not require writable temporary storage"
fi

for ext in json json5; do
	if printf '%s\n' "$first_output" | grep -Eq "^[0-9]{4}-[0-9]{2}-[0-9]{2} .* - (\./)?input\.$ext$"; then
		echo "PASS: modified input.$ext reported with a timestamp"
	else
		echo "FAIL: modified input.$ext was not reported with a timestamp"
		status=1
	fi
done

second_output="$({
	cd "$tmp" || exit 1
	formatter
})"
if [ -z "$second_output" ]; then
	echo "PASS: already formatted files are not reported"
else
	echo "FAIL: formatter reported files it did not modify:"
	printf '%s\n' "$second_output"
	status=1
fi

# Interactive shells announce commands launched with `&` using output such as
# "[1] 12345" and "[1] Done". The top-level formatter should not leak those
# job-control messages around its own timestamped file output.
interactive_output="$(bash --noprofile --norc -ic "source '$aliases'; cd '$tmp'; formatter" 2>&1)"
if printf '%s\n' "$interactive_output" | grep -Eq '^\[[0-9]+\]'; then
	echo "FAIL: formatter produced interactive job-control output:"
	printf '%s\n' "$interactive_output"
	status=1
else
	echo "PASS: formatter produces no interactive job-control output"
fi

# Project-wide formatters used to copy every candidate into a temporary
# directory. Exercise that path with a fake Terraform formatter while TMPDIR
# is unusable, and verify only the file it changes is reported.
terraform_project="$tmp/terraform-project"
mkdir -p "$terraform_project/bin"
printf 'before\n' >"$terraform_project/changed.tf"
printf 'stable\n' >"$terraform_project/stable.tf"
cat >"$terraform_project/bin/terraform" <<'EOF'
#!/usr/bin/env bash
[ "$1" = fmt ] && [ "$2" = --recursive ] || exit 2
printf 'after\n' >changed.tf
EOF
chmod +x "$terraform_project/bin/terraform"

terraform_output="$({
	cd "$terraform_project" || exit 1
	PATH="$terraform_project/bin:$PATH" TMPDIR="$unusable_tmp" formatter
} 2>&1)"
if [ "$(printf '%s\n' "$terraform_output" | grep -c .)" -eq 1 ] &&
	printf '%s\n' "$terraform_output" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2} .* - (\./)?changed\.tf$'; then
	echo "PASS: project-wide formatter snapshots stay in memory"
else
	echo "FAIL: project-wide formatter produced unexpected output:"
	printf '%s\n' "$terraform_output"
	status=1
fi

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
