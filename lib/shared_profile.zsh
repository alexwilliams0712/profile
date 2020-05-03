# Initialise the IMS ZSH Profile
# A lot to be taken from https://gist.github.com/butlerx/753f754f854f7ae97783

##
# PATH MANIPULATION
##
path_append ()  { path_remove $1; export PATH="$PATH:$1"; }
path_prepend () { path_remove $1; export PATH="$1:$PATH"; }

# Careful to specify the full name or the delete will be partial!
function path_remove {
  # delete any instances in the middle or at the end
  PATH=${PATH/":$1"/}
  # delete any instances at the beginning
  PATH=${PATH/"$1:"/}
  export PATH
}

# Pretty PATH - Show PATH in a more readable way than path1:path2:path3...
alias ppath='for i ($path) { print $i }'

# Put Cygwin bin, Git, Perl & Python on top of PATH - We want to use the system Python etc, not the Cygwin ones
path_prepend "/usr/local/bin:/usr/bin"
path_prepend "/cygdrive/c/Program Files/Git/cmd"
path_prepend "/cygdrive/c/Perl/bin:/cygdrive/c/Perl/site/bin"

if [ -d "/cygdrive/c/Python36" ]; then
    # Replace Python2 by Python3 in PATH
    path_remove "/cygdrive/c/Python27:/cygdrive/c/Python27/Scripts"
    path_prepend "/cygdrive/c/Python36:/cygdrive/c/Python36/Scripts"
else
    echo "Python3 isn't installed on your machine! :( \nFix this by running 'choco install Python36'"
fi

# To use Python2, just create virtualenv using the below command
# mkvirtualenv python2 -p C:/Python27/python.exe

# Add Angular CLI location in PATH if it exists
if [ -f "/cygdrive/c/Users/$USERNAME/AppData/Roaming/npm/ng" ]; then
    path_prepend "/cygdrive/c/Users/$USERNAME/AppData/Roaming/npm"
fi

# Similar to virtualenv activate script, put Anaconda on top of PATH and handles deactivation. Expects the version in parameter (2 or 3)
function anaconda_activation {
    # Verify first that Anaconda is installed
    if [ -d "/cygdrive/c/Anaconda$1" ]; then
        # If we were previously in a venv or if this function was already called, deactivate it
        deactivate 2> /dev/null
        ANACONDA_PATH=/cygdrive/c/Anaconda$1:/cygdrive/c/Anaconda$1/Scripts:/cygdrive/c/Anaconda$1/Library/bin
        path_prepend $ANACONDA_PATH
        # This is so our function virtualenv_info() detects our change and adjust PROMPT
        export VIRTUAL_ENV=Anaconda$1
        # Reverts the changes when run
        function deactivate () {
            path_remove $ANACONDA_PATH
            unset VIRTUAL_ENV
            unset ANACONDA_PATH
            # Self destruct!
            unset -f deactivate
        }
    else
        echo "Anaconda$1 is not installed in /cygdrive/c, run 'choco install Anaconda$1' or raise ITS"
    fi
}

workon_anaconda2 () { anaconda_activation 2 }
workon_anaconda3 () { anaconda_activation 3 }


##
# GLOBAL VARIABLES
##
# Easy access to the Desktop
export DESKTOP=/cygdrive/c/Users/$USERNAME/Desktop


# Check that CODE_ROOT variable is already set on a system level
if [[ -z "${CODE_ROOT}" ]]; then
    echo "CODE_ROOT environment variable is not defined. Contact ITSA."
    exit 1
fi

# Define CODE_ROOT depending on what drives exist
if [ -d "/cygdrive/d" ]; then
    export CODE_ROOT=/cygdrive/d/Code
fi

if [ -d "/cygdrive/e" ]; then
    export CODE_ROOT=/cygdrive/e/CODE
fi


# Also create subfolders git and svn if they do not exist.
mkdir -p $CODE_ROOT/git

# move user away from network homedrive: cd to code root if not already in a sub-dir
test  ${PWD#*$CODE_ROOT} = $PWD && {
    cd $CODE_ROOT
}


# If virtualenvwrapper is installed in Python3:
if [ -f "/cygdrive/c/Python36/Scripts/virtualenvwrapper.sh" ]; then
    # Put in place virtualenvwrapper's architecture and logic in place.
    mkdir -p $CODE_ROOT/.virtualenvs
    export WORKON_HOME=$CODE_ROOT/.virtualenvs
    source /cygdrive/c/Python36/Scripts/virtualenvwrapper.sh
    # Override the below to have the correct value on Windows
    VIRTUALENVWRAPPER_ENV_BIN_DIR="Scripts"
fi


autoload -U colors && colors

# Doesn't consider / to be a word delimiter, so ^backspace just deletes the last directory, not the entire current argument
autoload -U select-word-style
select-word-style bash


##
# COMPLETION OPTIONS
##
autoload -U compinit
compinit

# if we use two // in a row it won't try to expand between them - this means we can tab-complete on network drives, e.g. //grdeploy/blah
# won't try to complete on network drive names because it's slow
# also don't try to complete in <letter>:/ so tab-completion works on paths such as d:/data/blah
zstyle ':completion:*' preserve-prefix '(*:/|//*/)'

# Make the current selection become highlighted when tab completing
zstyle ':completion:*' menu select=2

# case-insensitive completion, nicked from http://hintsforums.macworld.com/archive/index.php/t-6493.html
# case-insensitive,partial-word and then substring completion
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'

# Exclude .dll from suggested completion
zstyle ':completion:*' ignored-patterns '*.dll'


##
# HISTORY OPTIONS
##
HISTFILE=~/.zsh_history          # store history in $HOME
HISTSIZE=50000                   # big history
SAVEHIST=50000                   # big history

setopt BANG_HIST                 # Treat the '!' character specially during expansion.
setopt INC_APPEND_HISTORY        # Write to the history file immediately, not when the shell exits.
setopt HIST_EXPIRE_DUPS_FIRST    # Expire duplicate entries first when trimming history.
setopt HIST_IGNORE_DUPS          # Don't record an entry that was just recorded again.
setopt HIST_IGNORE_ALL_DUPS      # Delete old recorded entry if new entry is a duplicate.
setopt HIST_FIND_NO_DUPS         # Do not display a line previously found.
setopt HIST_IGNORE_SPACE         # Don't record an entry starting with a space.
setopt HIST_SAVE_NO_DUPS         # Don't write duplicate entries in the history file.
setopt HIST_REDUCE_BLANKS        # Remove superfluous blanks before recording entry.
setopt HIST_VERIFY               # Don't execute immediately upon history expansion.
setopt HIST_BEEP                 # Beep when accessing nonexistent history.


##
# PROMPT OPTIONS
##
setopt PROMPT_SUBST              # Recalculates the function inside the PROMPT for each new line

# disable the default virtualenv prompt change
export VIRTUAL_ENV_DISABLE_PROMPT=1

# return the following format when virtualenv are activated: '(env)''
function virtualenv_info(){
    # Get Virtual Env
    if [ -n "$VIRTUAL_ENV" ]; then
        # Strip out the path and just leave the env name
        echo "%{$fg[magenta]%}("`basename $VIRTUAL_ENV`") %{$reset_color%}"
    fi
}

# It is possible to use the ZSH-embeded feature vcs_info to retrive Git related information.
# However it substantially slows Cygwin down, the below function is quicker if all we want is to output the active branch name.
# For more info, see http://arjanvandergaag.nl/blog/customize-zsh-prompt-with-vcs-info.html
function git_info(){
    # Only run this if we're inside a git directory
    if [ $(git rev-parse --is-inside-work-tree 2>/dev/null) ]; then
        echo "%{$fg[cyan]%}["`basename $(git symbolic-ref HEAD)`"]%{$reset_color%}"
    fi
}

NEWLINE=$'\n'
PROMPT="${NEWLINE}\$(virtualenv_info)%{$fg[green]%}%n@%m %{$reset_color%}%{$fg[yellow]%}%~%{$reset_color%} \$(git_info)${NEWLINE}$ "


# Make title bar say something useful
function chpwd { print -Pn "\e]2; %~\a" }

# Disable Cygwin DOS-like paths warning messages
export CYGWIN="nodosfilewarning"


##
# KEY BINDINGS
##
bindkey "\e[H"      beginning-of-line           # home
bindkey "\e[F"      end-of-line                 # end
bindkey "\e[5~"     beginning-of-history        # page up
bindkey "\e[6~"     end-of-history              # page down
bindkey "^[[A"      history-search-backward     # ctrl-r followed by page up
bindkey "^[[B"      history-search-forward      # ctrl-r followed by page down
bindkey "\e[3~"     delete-char                 # delete
bindkey "^H"        backward-delete-char        # backspace
bindkey "\e[1;5C"   forward-word                # ctrl-Right arrow
bindkey "\e[1;5D"   backward-word               # ctrl-Left arrow
bindkey '^i'        expand-or-complete-prefix   # completion in the middle of a line
bindkey "^K"        kill-whole-line             # ctrl-k
