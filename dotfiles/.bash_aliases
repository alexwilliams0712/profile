export CODE_ROOT=$HOME/CODE
export KUBECONFIG=~/.kube/config

# Allow modification without restarting terminal
alias refresh='source ~/.bashrc'
alias reload='refresh'

# Make grep always show color and enable Regex, which is normally a default behavior on Linux
alias grep='grep --color=auto -E'

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

function attackoftheclones() {
   # Get the organization name from the function argument
    ORG_NAME="$1"

    # Get a list of all repositories in the organization
    REPO_URLS=$(curl -s "https://api.github.com/orgs/${ORG_NAME}/repos?per_page=1000" | grep -o 'git@[^"]*')

    # Clone or pull each repository
    for REPO_URL in $REPO_URLS; do
        REPO_NAME=$(echo "$REPO_URL" | cut -d':' -f2 | sed 's/.git//')
        if [ -d "$REPO_NAME" ]; then
            echo "Repository already exists: $REPO_NAME"
            cd "$REPO_NAME"
            git pull
            cd ..
        else
            echo "Cloning repository: $REPO_URL"
            git clone "$REPO_URL"
        fi
    done
}

# Python
# alias pip-compile="sort requirements.in -o requirements.in; pip-compile"

# Sublime Text
alias st=subl

##
#general
##
alias gohome="cd $CODE_ROOT"

##
#git
##
alias gitthefuckout="git reset HEAD --hard; git clean -fd; git pull --all"
alias multipull="find . -mindepth 1 -maxdepth 1 -type d -print -exec git -C {} pull \;"

##
#K8s
##
alias k9s="k9s-nsg"

alias dockoff='docker rm -vf $(docker ps -aq); docker rmi -f $(docker images -aq)'
alias dockercontainers='docker ps --format="table {{.Names}}\t{{.Image}}\t{{.Status}}" | (read -r; printf "%s\n" "$REPLY"; sort -k 1 )'

