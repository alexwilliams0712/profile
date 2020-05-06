# Allow modification without restarting terminal
alias refresh='source ~/.zshrc'
alias reload='refresh'

# Global alias - ZSH trick - Handy way to silent any verbose command, just append 'quiet' to it
alias -g QUIET='> /dev/null 2>&1 &'

# Make grep always show color and enable Regex, which is normally a default behavior on Linux
alias grep='grep --color=auto -E'

# Open a Windows explorer in the current dir
alias explore='explorer .'


##
# LS ALIASES
##
alias ls='ls -F'
alias l='ls -c'                 # show most recent files first
alias la='ls -A'                # show all (including '.files', exluding ./ and ../)
alias ll='ls -lAh'              # show all as a list sorted alphabetically
alias llf='ll | grep -vE "^d"'  # ll files only
alias lt='ls -lArth'            # show all as a list sorted by reversed modification time


##
# CD ALIASES
##
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias bk='cd $OLDPWD'


# Grep and Tail fix logs easily by placing a separator bewtween fields
function grepcfix() {
   \grep --color=always $@ | sed 's/\x1/|/g'
}

function tailfix() {
   \tail -f  $@ | sed 's/\x1/|/g'
}


##
# EDITORS
##


# VSCode
code () { VSCODE_CWD="$PWD" open -n -b "com.microsoft.VSCode" --args $* ;}

# Sublime Text
st() { sublime & }

mkrequirements() {
    local requirements="requirements.in"
    echo "# $($(command -v python) --version)" > $requirements
    pip freeze >> $requirements
}


alias b=$CODE_ROOT/.devtools/Scripts/black.exe

##
#git
##
alias multipull="cd $CODE_ROOT/git; find . -mindepth 1 -maxdepth 2 -type d -print -exec git -C {} pull --all \;"
alias co="checkout"


##
#Python Dev
##
alias b=$CODE_ROOT/.devtools/bin/black
alias pylint="python -m pylint **/*.py --exit-zero"


##
#general
##
alias gohome="cd $CODE_ROOT"
