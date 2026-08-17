#!/bin/bash
# macOS system-tool validation helpers, isolated for focused tests.

clt_receipt_exists() {
	/usr/sbin/pkgutil --pkg-info=com.apple.pkg.CLTools_Executables &>/dev/null
}

standalone_command_line_tools_exist() {
	[ -d /Library/Developer/CommandLineTools ]
}

available_command_line_tools_label() {
	/usr/sbin/softwareupdate --list 2>&1 |
		grep -B 1 -E 'Command Line Tools' |
		awk -F'*' '/^ *\*/ {print $2}' |
		sed -e 's/^ *Label: //' -e 's/^ *//' |
		sort -V |
		tail -n 1
}

command_line_tools_label_if_required() {
	if [ "$1" != true ]; then
		return 1
	fi
	available_command_line_tools_label
}

move_stale_command_line_tools() {
	local clt_dir="/Library/Developer/CommandLineTools"
	local stale_clt_backup

	stale_clt_backup="${clt_dir}.stale-$(date '+%Y%m%d%H%M%S').$$"
	log "Moving stale standalone Command Line Tools to $stale_clt_backup"
	/usr/bin/sudo -n /bin/mv "$clt_dir" "$stale_clt_backup"
}

command_line_tools_are_current() {
	local brew_doctor_output

	clt_receipt_exists || return 1
	if ! command -v brew >/dev/null 2>&1; then
		return 0
	fi
	brew_doctor_output="$(brew doctor 2>&1 || true)"
	if printf '%s\n' "$brew_doctor_output" |
		grep -qiE 'Command Line Tools are too outdated|outdated Command Line Tools|Xcode alone is not sufficient'; then
		return 1
	fi
}

brew_requires_standalone_command_line_tools() {
	local brew_doctor_output

	if ! command -v brew >/dev/null 2>&1; then
		return 1
	fi
	brew_doctor_output="$(brew doctor 2>&1 || true)"
	printf '%s\n' "$brew_doctor_output" | grep -qi 'Xcode alone is not sufficient'
}

command_line_tools_update_required() {
	local full_xcode_available="$1"

	if command_line_tools_are_current; then
		return 1
	fi
	if [ "$full_xcode_available" = true ] && ! standalone_command_line_tools_exist &&
		! brew_requires_standalone_command_line_tools; then
		return 1
	fi
}

use_full_xcode_for_invalid_command_line_tools() {
	local full_xcode_available="$1"

	if command_line_tools_are_current; then
		return 0
	fi
	if [ "$full_xcode_available" = false ] || brew_requires_standalone_command_line_tools; then
		return 1
	fi
	if standalone_command_line_tools_exist; then
		move_stale_command_line_tools || return 1
	fi
	log "Standalone Command Line Tools remain invalid; using the active full Xcode toolchain."
}
