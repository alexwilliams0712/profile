# ~/.profile: executed by the command interpreter for login shells.
# This file is not read by bash(1), if ~/.bash_profile or ~/.bash_login
# exists.
# see /usr/share/doc/bash/examples/startup-files for examples.
# the files are located in the bash-doc package.

# the default umask is set in /etc/profile; for setting the umask
# for ssh logins, install and configure the libpam-umask package.
#umask 022

# if running bash
if [ -n "$BASH_VERSION" ]; then
    # include .bashrc if it exists
    if [ -f "$HOME/.bashrc" ]; then
	. "$HOME/.bashrc"
    fi
fi

# set PATH so it includes user's private bin if it exists
if [ -d "$HOME/bin" ] ; then
    PATH="$HOME/bin:$PATH"
fi

# set PATH so it includes user's private bin if it exists
if [ -d "$HOME/.local/bin" ] ; then
    PATH="$HOME/.local/bin:$PATH"
fi

# set PATH so it includes rust/cargo binaries if they exist
if [ -d "$HOME/.cargo/bin" ] ; then
    PATH="$HOME/.cargo/bin:$PATH"
fi

# Deduplicate PATH, preserving order (exact match, not substring)
declare -A _seen_paths
_new_path=()
IFS=: read -ra _path_parts <<<"$PATH"
for _p in "${_path_parts[@]}"; do
    if [ -n "$_p" ] && [ -z "${_seen_paths[$_p]:-}" ]; then
        _seen_paths["$_p"]=1
        _new_path+=("$_p")
    fi
done
IFS=:
export PATH="${_new_path[*]}"
unset IFS _seen_paths _new_path _path_parts _p
