# ~/.bashrc: executed by bash(1) for non-login shells.
# see /usr/share/doc/bash/examples/startup-files (in the package bash-doc)
# for examples

# If not running interactively, don't do anything
case $- in
*i*) ;;
*) return ;;
esac

# Suppress macOS bash deprecation warning
export BASH_SILENCE_DEPRECATION_WARNING=1

# Homebrew (Apple Silicon)
if [ -x /opt/homebrew/bin/brew ]; then
	eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# don't put duplicate lines or lines starting with space in the history.
# See bash(1) for more options
HISTCONTROL=ignoreboth

# append to the history file, don't overwrite it
shopt -s histappend

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=1000
HISTFILESIZE=2000

# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# If set, the pattern "**" used in a pathname expansion context will
# match all files and zero or more directories and subdirectories.
#shopt -s globstar

# make less more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
	debian_chroot=$(cat /etc/debian_chroot)
fi

# set a fancy prompt (non-color, unless we know we "want" color)
case "$TERM" in
xterm-color | *-256color) color_prompt=yes ;;
esac

# uncomment for a colored prompt, if the terminal has the capability; turned
# off by default to not distract the user: the focus in a terminal window
# should be on the output of commands, not on the prompt
#force_color_prompt=yes

if [ -n "$force_color_prompt" ]; then
	if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
		# We have color support; assume it's compliant with Ecma-48
		# (ISO/IEC-6429). (Lack of such support is extremely rare, and such
		# a case would tend to support setf rather than setaf.)
		color_prompt=yes
	else
		color_prompt=
	fi
fi

if [ "$color_prompt" = yes ]; then
	PS1='\n${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
else
	PS1='\n${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
fi
unset color_prompt force_color_prompt

# If this is an xterm set the title to user@host:dir
case "$TERM" in
xterm* | rxvt*)
	PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
	;;
*) ;;
esac

# enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
	test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
	alias ls='ls --color=auto'
	#alias dir='dir --color=auto'
	#alias vdir='vdir --color=auto'

	alias grep='grep --color=auto'
	alias fgrep='fgrep --color=auto'
	alias egrep='egrep --color=auto'
fi

# colored GCC warnings and errors
#export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# gsettings (Linux/GNOME only)
if [ "$(uname)" = "Linux" ] && command -v gsettings >/dev/null 2>&1; then
	gsettings set org.gnome.desktop.interface text-scaling-factor 0.95
	gsettings set org.gnome.desktop.interface cursor-size 24
fi

# some more ls aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# Add an "alert" alias for long running commands.  Use like so:
#   sleep 10; alert
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'

#  Codes to color our prompt
RED="\[\033[0;31m\]"
YELLOW="\[\033[1;33m\]"
GREEN="\[\033[0;32m\]"
BLUE="\[\033[1;34m\]"
LIGHT_BLUE="\[\033[1;36m\]"
PURPLE="\[\033[1;35m\]"
LIGHT_RED="\[\033[1;31m\]"
LIGHT_GREEN="\[\033[1;32m\]"
WHITE="\[\033[1;37m\]"
LIGHT_GRAY="\[\033[0;37m\]"
COLOR_NONE="\[\e[0m\]"

export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PYENV_ROOT/shims:$PATH"
export PATH=$PATH:$HOME/.local/share/JetBrains/Toolbox/scripts
export PATH=$PATH:$HOME/.local/bin
export PATH="$HOME/go/bin:$PATH"
if command -v pyenv >/dev/null 2>&1; then
	alias brew='env PATH="${PATH//$(pyenv root)\/shims:/}" brew'
	# Lazy-load pyenv init (saves ~2s on shell startup).
	# The shims directory is already on PATH above, so pyenv version
	# selection works immediately. Full init runs on first use of
	# python/pip/pyenv to set up completions and virtualenv hooks.
	_pyenv_init() {
		unset -f python python3 pip pip3 pyenv
		eval "$(command pyenv init --path)"
		eval "$(command pyenv init -)"
	}
	python()  { _pyenv_init; python "$@"; }
	python3() { _pyenv_init; python3 "$@"; }
	pip()     { _pyenv_init; pip "$@"; }
	pip3()    { _pyenv_init; pip3 "$@"; }
	pyenv()   { _pyenv_init; pyenv "$@"; }
fi

# npm
export PATH=~/.npm-global/bin:$PATH

hg_branch() {
	hg branch 2>/dev/null | awk '{print "hg["$1"] "}'
}

git_branch() {
	git branch 2>/dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/git[\1] /'
}

pyenv_python_version() {
	pyenv global 2>/dev/null || echo "No pyenv global"
}

# Set the full bash prompt
function set_bash_prompt() {
	# Check if VIRTUAL_ENV is set and not empty
	if [ -z "$VIRTUAL_ENV" ]; then
		ENV_NAME=$(pyenv_python_version)
	else
		ENV_NAME=$(echo $VIRTUAL_ENV | awk -F'/' '{print $(NF-1)}')
	fi

	# Set the PS1 variable with the updated ENV_NAME
	PS1="${LIGHT_BLUE}${ENV_NAME} ${debian_chroot:+($debian_chroot)}${BLUE}\u${BLUE}@${BLUE}\h\[\033[00m\]:${YELLOW}\w\[\033[00m\] ${PURPLE}$(git_branch)$(hg_branch)${COLOR_NONE}$ "
}

# Alias definitions.
# You may want to put all your additions into a separate file like
# ~/.bash_aliases, instead of adding them here directly.
# See /usr/share/doc/bash-doc/examples in the bash-doc package.

if [ -f ~/.bash_aliases ]; then
	. ~/.bash_aliases
fi

if [ -f ~/.personal ]; then
	. ~/.personal
fi

# enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
# sources /etc/bash.bashrc).
if ! shopt -oq posix; then
	if [ -f /usr/share/bash-completion/bash_completion ]; then
		. /usr/share/bash-completion/bash_completion
	elif [ -f /etc/bash_completion ]; then
		. /etc/bash_completion
	elif [ -f /opt/homebrew/etc/profile.d/bash_completion.sh ]; then
		. /opt/homebrew/etc/profile.d/bash_completion.sh
	fi
fi

# Carapace - universal tab completions
if command -v carapace >/dev/null 2>&1; then
	source <(carapace _carapace bash)
fi

# Starship prompt, or fall back to custom prompt
if command -v starship >/dev/null 2>&1; then
	eval "$(starship init bash)"
else
	PROMPT_COMMAND=set_bash_prompt
fi

echo "Profile version: $(cat $HOME/BASH_PROFILE_VERSION)"
# if command -v pyenv >/dev/null 2>&1; then pyenv --version; fi
# if command -v uv >/dev/null 2>&1; then uv --version; fi
# if command -v python3 >/dev/null 2>&1; then python3 --version; fi
