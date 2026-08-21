#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"

# shellcheck disable=SC1091
source "$repo_root/tools/common.sh"
# shellcheck disable=SC1091
source "$repo_root/tools/macos_helpers.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"

# shellcheck disable=SC2016
printf '%s\n' \
	'#!/bin/bash' \
	'if [ "$*" = "info --cask self-updating" ]; then' \
	'  printf "==> self-updating: 1.0 (auto_updates)\\n"' \
	'elif [ "$*" = "info --cask incomplete-self-updating" ]; then' \
	'  printf "==> incomplete-self-updating: 1.0 (auto_updates)\\n"' \
	'elif [ "$*" = "info --cask managed-update" ]; then' \
	'  printf "==> managed-update: 1.0\\n"' \
	'elif [ "${PROFILE_TEST_BREW_OUTDATED:-0}" = 1 ]; then' \
	'  printf "Warning: Your Command Line Tools are too outdated.\\n"' \
	'elif [ "${PROFILE_TEST_BREW_OUTDATED:-0}" = 2 ]; then' \
	'  printf "Warning: A newer Command Line Tools release is available.\\n"' \
	'elif [ "${PROFILE_TEST_BREW_OUTDATED:-0}" = 3 ]; then' \
	'  printf "Error: Xcode alone is not sufficient on this macOS release.\\n"' \
	'fi' >"$tmp/bin/brew"
chmod +x "$tmp/bin/brew"

export PATH="$tmp/bin:/usr/bin:/bin"

clt_receipt_exists() {
	return "${PROFILE_TEST_PKGUTIL_STATUS:-0}"
}

standalone_command_line_tools_exist() {
	return "${PROFILE_TEST_CLT_DIR_STATUS:-1}"
}

move_stale_command_line_tools() {
	printf 'called\n' >>"$tmp/sudo.log"
}

available_command_line_tools_label() {
	printf 'called\n' >>"$tmp/softwareupdate.log"
	printf '%s\n' 'Command Line Tools fixture'
}

if grep -q 'HOMEBREW_NO_INSTALL_FROM_API=' "$repo_root/tools/setup_macos.sh" ||
	! grep -Eq '^unset .*HOMEBREW_NO_INSTALL_FROM_API' "$repo_root/tools/setup_macos.sh"; then
	printf '%s\n' 'FAIL: Homebrew API opt-out is not unconditionally unset'
	exit 1
fi
if grep -REq 'PROFILE_SETUP_(CLT|PKGUTIL|SUDO)' \
	"$repo_root/tools/setup_macos.sh" "$repo_root/tools/macos_helpers.sh"; then
	printf '%s\n' 'FAIL: privileged CLT targets are environment-selectable'
	exit 1
fi
if grep -Eq '/usr/bin/sudo +-n' "$repo_root/tools/setup_macos.sh" \
	"$repo_root/tools/macos_helpers.sh"; then
	printf '%s\n' 'FAIL: macOS CLT recovery still assumes a valid sudo timestamp'
	exit 1
fi
if ! cask_auto_updates self-updating || cask_auto_updates managed-update; then
	printf '%s\n' 'FAIL: self-updating cask detection is incorrect'
	exit 1
fi
cask_has_missing_app_artifact() {
	[ "$1" = incomplete-self-updating ]
}
selected_casks="$(casks_managed_by_own_updater \
	self-updating managed-update incomplete-self-updating)"
# shellcheck disable=SC2016 # The production variable reference is intentional.
if [ "$selected_casks" != self-updating ] ||
	! grep -Fq 'HOMEBREW_BUNDLE_CASK_SKIP="$bundle_skipped_casks"' \
		"$repo_root/tools/setup_macos.sh"; then
	printf '%s\n' 'FAIL: cask bundle skip does not contain exactly valid self-updating apps'
	exit 1
fi

# shellcheck disable=SC2329 # Invoked indirectly by the cask skip helper.
tailscale_is_installed() {
	return 1
}
TAILSCALE_UPGRADE_REQUESTED=false
selected_casks="$(casks_skipped_from_bundle self-updating tailscale-app managed-update)"
if [ "$selected_casks" != self-updating ]; then
	printf '%s\n' 'FAIL: an absent Tailscale app was excluded from fresh installation'
	exit 1
fi
# shellcheck disable=SC2329 # Invoked indirectly by the cask skip helper.
tailscale_is_installed() {
	return 0
}
selected_casks="$(casks_skipped_from_bundle self-updating tailscale-app managed-update)"
if [ "$selected_casks" != 'self-updating tailscale-app' ]; then
	printf '%s\n' 'FAIL: an installed Tailscale app was not protected from bundle upgrades'
	exit 1
fi
# shellcheck disable=SC2034 # Read by the sourced macOS helper.
TAILSCALE_UPGRADE_REQUESTED=true
selected_casks="$(casks_skipped_from_bundle self-updating tailscale-app managed-update)"
if [ "$selected_casks" != self-updating ]; then
	printf '%s\n' 'FAIL: an approved Tailscale upgrade remained excluded from Homebrew Bundle'
	exit 1
fi

prompt_line="$(awk '/^main\(\) \{/ { in_main = 1 } in_main && /collect_tailscale_upgrade_preference/ { print NR; exit }' \
	"$repo_root/tools/setup_macos.sh")"
first_step_line="$(awk '/^main\(\) \{/ { in_main = 1 } in_main && /run_functions/ { print NR; exit }' \
	"$repo_root/tools/setup_macos.sh")"
# shellcheck disable=SC2016 # The production variable reference is intentional.
repair_guard_line="$(grep -nF '[ "$cask" = tailscale-app ] && tailscale_upgrade_is_declined' \
	"$repo_root/tools/setup_macos.sh" | cut -d: -f1)"
# shellcheck disable=SC2016 # The production variable reference is intentional.
repair_action_line="$(grep -nF 'brew reinstall --cask --force "$cask"' \
	"$repo_root/tools/setup_macos.sh" | head -n 1 | cut -d: -f1)"
if [ -z "$prompt_line" ] || [ -z "$first_step_line" ] || [ "$prompt_line" -ge "$first_step_line" ]; then
	printf '%s\n' 'FAIL: the Tailscale upgrade choice is not collected before macOS setup steps'
	exit 1
fi
if [ -z "$repair_guard_line" ] || [ -z "$repair_action_line" ] ||
	[ "$repair_guard_line" -ge "$repair_action_line" ]; then
	printf '%s\n' 'FAIL: declined Tailscale upgrades are not protected from cask repairs'
	exit 1
fi
if grep -Eqi 'julia' "$repo_root/tools/setup_macos.sh" \
	"$repo_root/tools/macos_helpers.sh" "$repo_root/tools/Brewfile"; then
	printf '%s\n' 'FAIL: obsolete Julia cleanup is still part of macOS setup'
	exit 1
fi

fallback_line="$(grep -n 'use_full_xcode_for_invalid_command_line_tools' \
	"$repo_root/tools/setup_macos.sh" | head -n 1 | cut -d: -f1)"
update_line="$(grep -n 'Searching for Xcode Command Line Tools' \
	"$repo_root/tools/setup_macos.sh" | cut -d: -f1)"
if [ -z "$fallback_line" ] || [ -z "$update_line" ] || [ "$fallback_line" -ge "$update_line" ]; then
	printf '%s\n' 'FAIL: valid full Xcode is not preferred before standalone CLT updates'
	exit 1
fi
# shellcheck disable=SC2016
if grep -Fq 'brew list "$pkg"' "$repo_root/tools/setup_macos.sh" ||
	! grep -Fq 'brew list --formula' "$repo_root/tools/setup_macos.sh"; then
	printf '%s\n' 'FAIL: unwanted formula checks can re-clone homebrew/core'
	exit 1
fi

export PROFILE_TEST_PKGUTIL_STATUS=0
export PROFILE_TEST_BREW_OUTDATED=0
if ! command_line_tools_are_current; then
	printf '%s\n' 'FAIL: current Command Line Tools were rejected'
	exit 1
fi

export PROFILE_TEST_PKGUTIL_STATUS=1
if command_line_tools_are_current; then
	printf '%s\n' 'FAIL: missing Command Line Tools receipt was accepted'
	exit 1
fi

export PROFILE_TEST_PKGUTIL_STATUS=0
export PROFILE_TEST_BREW_OUTDATED=1
if command_line_tools_are_current; then
	printf '%s\n' 'FAIL: outdated Command Line Tools were accepted'
	exit 1
fi

export PROFILE_TEST_BREW_OUTDATED=2
if ! command_line_tools_are_current; then
	printf '%s\n' 'FAIL: advisory Command Line Tools update was treated as fatal'
	exit 1
fi

if command_line_tools_label_if_required false >/dev/null; then
	printf '%s\n' 'FAIL: optional CLT update unexpectedly returned a label'
	exit 1
fi
if [ -e "$tmp/softwareupdate.log" ]; then
	printf '%s\n' 'FAIL: optional CLT state invoked softwareupdate listing'
	exit 1
fi
if [ "$(command_line_tools_label_if_required true)" != 'Command Line Tools fixture' ] ||
	[ "$(wc -l <"$tmp/softwareupdate.log")" -ne 1 ]; then
	printf '%s\n' 'FAIL: required CLT state did not list updates exactly once'
	exit 1
fi

export PROFILE_TEST_BREW_OUTDATED=0
export PROFILE_TEST_PKGUTIL_STATUS=1
export PROFILE_TEST_CLT_DIR_STATUS=0
if ! command_line_tools_update_required true; then
	printf '%s\n' 'FAIL: stale standalone tools did not request an update'
	exit 1
fi
if ! use_full_xcode_for_invalid_command_line_tools true; then
	printf '%s\n' 'FAIL: full Xcode did not replace stale standalone tools'
	exit 1
fi
if [ "$(wc -l <"$tmp/sudo.log")" -ne 1 ]; then
	printf '%s\n' 'FAIL: stale standalone tools were not moved once'
	exit 1
fi

if ! command_line_tools_update_required false; then
	printf '%s\n' 'FAIL: invalid tools without Xcode did not request an update'
	exit 1
fi
if use_full_xcode_for_invalid_command_line_tools false; then
	printf '%s\n' 'FAIL: invalid standalone tools passed without full Xcode'
	exit 1
fi
if [ "$(wc -l <"$tmp/sudo.log")" -ne 1 ]; then
	printf '%s\n' 'FAIL: invalid tools were moved without a full Xcode fallback'
	exit 1
fi

export PROFILE_TEST_PKGUTIL_STATUS=0
before_sudo_calls="$(wc -l <"$tmp/sudo.log")"
if ! use_full_xcode_for_invalid_command_line_tools true; then
	printf '%s\n' 'FAIL: current standalone tools were rejected'
	exit 1
fi
if [ "$(wc -l <"$tmp/sudo.log")" -ne "$before_sudo_calls" ]; then
	printf '%s\n' 'FAIL: current standalone tools were modified'
	exit 1
fi

export PROFILE_TEST_PKGUTIL_STATUS=1
export PROFILE_TEST_CLT_DIR_STATUS=1
before_sudo_calls="$(wc -l <"$tmp/sudo.log")"
if command_line_tools_update_required true; then
	printf '%s\n' 'FAIL: Xcode-only state requested another standalone update'
	exit 1
fi
if ! use_full_xcode_for_invalid_command_line_tools true; then
	printf '%s\n' 'FAIL: full Xcode without standalone tools was rejected'
	exit 1
fi
if [ "$(wc -l <"$tmp/sudo.log")" -ne "$before_sudo_calls" ]; then
	printf '%s\n' 'FAIL: idempotent full Xcode fallback invoked sudo'
	exit 1
fi

export PROFILE_TEST_BREW_OUTDATED=3
if ! command_line_tools_update_required true; then
	printf '%s\n' 'FAIL: a mandatory standalone CLT state skipped its update'
	exit 1
fi
if use_full_xcode_for_invalid_command_line_tools true; then
	printf '%s\n' 'FAIL: full Xcode was accepted when Homebrew requires standalone CLT'
	exit 1
fi
if [ "$(wc -l <"$tmp/sudo.log")" -ne "$before_sudo_calls" ]; then
	printf '%s\n' 'FAIL: mandatory standalone CLT state moved files before failing'
	exit 1
fi

sudo_command() {
	printf '%s\n' "$*" >>"$tmp/foreground-sudo.log"
	[ "$*" != '-n -v' ]
}
run_sudo_output="$(run_sudo /bin/mv source target)"
if ! grep -Fxq -- '-n -v' "$tmp/foreground-sudo.log" ||
	! grep -Fxq -- '/bin/mv source target' "$tmp/foreground-sudo.log" ||
	[[ "$run_sudo_output" != *'Administrator approval is required to continue.'* ]]; then
	printf '%s\n' 'FAIL: invalidated sudo credentials did not fall back visibly'
	exit 1
fi

printf '%s\n' 'PASS: Homebrew API and Command Line Tools state are validated'
