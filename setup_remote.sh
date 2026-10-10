#!/bin/bash
# Run the profile setup here and on other machines at once, in one tmux window.
# This machine takes the left pane; each chosen machine gets a pane on the right.
#   bash setup_remote.sh             choose machines, then run setup everywhere
#   bash setup_remote.sh --select    print the chosen machines only
#   bash setup_remote.sh host...     run setup here and on the given machines
# Machines come from the Syncthing-shared tmux_ai hosts list. Remote runs use
# their own tmux session, so package upgrades cannot cut them off.

hosts_file="$HOME/dotfiles/tmux_ai/hosts"
session=profile-setup

# Tailscale names match the SSH targets; macOS `hostname -s` does not.
self_name() {
	local self
	self=$(tailscale status --peers=false 2>/dev/null | awk 'NR == 1 { print $2 }')
	printf '%s\n' "${self:-$(hostname -s)}"
}

select_hosts() {
	local self others
	[ -f "$hosts_file" ] && command -v gum >/dev/null 2>&1 && command -v tmux >/dev/null 2>&1 || return 0
	self=$(self_name)
	others=$(awk -v self="$self" '!/^[[:space:]]*(#|$)/ && $1 != self { print $1 }' "$hosts_file")
	[ -n "$others" ] || return 0
	# shellcheck disable=SC2086 # One host name per word.
	gum choose --no-limit --header "Also run setup on (space selects, enter confirms):" $others |
		tr '\n' ' '
}

run_hosts() {
	local repo_dir rel_dir host remote
	repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)" || return 1
	rel_dir="${repo_dir#"$HOME"/}"
	if [ "$rel_dir" = "$repo_dir" ]; then
		echo "Error: $repo_dir is not under \$HOME, so its remote path is unknown." >&2
		return 1
	fi
	if tmux has-session -t "=$session" 2>/dev/null; then
		echo "Error: setup is already running; attach with: tmux attach -t $session" >&2
		return 1
	fi
	# PROFILE_SETUP_LOCAL_ONLY stops each run from offering machines again.
	local setup="PROFILE_SETUP_LOCAL_ONLY=1 bash -c 'source setup_entry.sh'"
	tmux new-session -d -s "$session" -c "$repo_dir" "$setup" || return 1
	# Keep failed panes open so their errors stay readable.
	tmux set-option -t "$session" remain-on-exit on
	for host in "$@"; do
		remote="cd ~/'$rel_dir' && tmux new-session -A -s $session \"$setup\" \\; set status off"
		tmux split-window -t "$session" "ssh -t $host $(printf '%q' "$remote")"
	done
	tmux set-window-option -t "$session" main-pane-width 50%
	tmux select-layout -t "$session" main-vertical
	tmux select-pane -t "$session:.0"
	if [ -n "${TMUX:-}" ]; then
		tmux switch-client -t "=$session"
		return
	fi
	tmux attach -t "=$session"
}

case "${1:-}" in
--select) select_hosts ;;
'')
	read -ra chosen <<<"$(select_hosts)"
	run_hosts "${chosen[@]}"
	;;
*)
	# Accept one space-separated argument, as printed by --select.
	read -ra chosen <<<"$*"
	run_hosts "${chosen[@]}"
	;;
esac
