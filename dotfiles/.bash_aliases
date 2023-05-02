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

function murder() {
    target_process=$1

    # Check if the target_process is non-empty
    if [ -z "${target_process}" ]; then
        echo "Error: Please provide a process name."
        return 1
    fi

    # Find processes with the target name and store their PIDs
    pids=$(ps aux | grep -i "${target_process}" | grep -v "grep" | awk '{print $2}')

    # Send SIGTERM to the processes and wait for 2 seconds
    for pid in $pids; do
        echo "Attempting graceful shutdown: $target_process - $pid"
        kill -15 $pid
    done

    sleep 2

    # Check if the processes are still running, and if so, send SIGKILL
    for pid in $pids; do
        if ps -p $pid > /dev/null; then
            echo "Having to kill: $target_process - $pid"
            kill -9 $pid
        fi
    done
}


function attackoftheclones() {
   # Get the organization name from the function argument
    ORG_NAME="$1"

    # Clone or pull each repository
    for REPO_NAME in $(gh repo list "${ORG_NAME}" --json=name --limit 1000 | jq -r '.[].name'); do
        if [ -d "$REPO_NAME" ]; then
            echo "Repository already exists: $REPO_NAME"
            cd "$REPO_NAME"
            git checkout main
            git pull
            cd ..
        else
            echo "Cloning repository: ${ORG_NAME}/${REPO_NAME}"
            gh repo clone ${ORG_NAME}/${REPO_NAME}
        fi
    done
}

# Python
# alias pip-compile="sort requirements.in -o requirements.in; pip-compile"

# Sublime Text
alias st=subl

# Pycharm
if [ -f "$HOME/.local/share/JetBrains/Toolbox/scripts/pycharm" ]; then
    alias charm="pycharm . &>/dev/null &"
fi

##
#general
##
alias gohome="cd $CODE_ROOT"

##
#git
##
function gitthefuckout() {
  git ls-remote --exit-code --heads origin main >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    git fetch origin && git reset --hard origin/main
  else
    git fetch origin && git reset --hard origin/master
  fi
}

alias multipull="find . -mindepth 1 -maxdepth 1 -type d -print -exec git -C {} pull \;"

##
#K8s
##
alias k9s="k9s-nsg"

alias dockoff='docker rm -vf $(docker ps -aq); docker rmi -f $(docker images -aq)'
alias dockercontainers='docker ps --format="table {{.Names}}\t{{.Image}}\t{{.Status}}" | (read -r; printf "%s\n" "$REPLY"; sort -k 1 )'
alias dockerperv='watch -n 1 "docker ps --format '\''table {{.Names}}\t{{.Image}}\t{{.Status}}'\''"'
