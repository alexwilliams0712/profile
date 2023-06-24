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
alias ppath='IFS=:; for i in $PATH; do echo $i; done; unset IFS'
alias ppypath='IFS=:; for i in $PYTHONPATH; do echo $i; done; unset IFS'

# Grep and Tail fix logs easily by placing a separator bewtween fields
function grepcfix() {
   \grep --color=always $@ | sed 's/\x1/|/g'
}

function tailfix() {
   \tail -f  $@ | sed 's/\x1/|/g'
}

function murder() {
    if [ "$#" -eq 0 ]; then
        echo "Error: Please provide at least one process name."
        return 1
    fi

    for target_process in "$@"; do
        echo "Killing all $target_process processes"
        # Declare an associative array for PIDs and commands
        declare -A pid_command_map

        # Send SIGTERM to the processes and wait for 2 seconds
        
        while IFS= read -r line; do
            pid=$(echo "$line" | awk '{print $2}')
            cmd=$(echo "$line" | awk '{print $11}')
            pid_command_map["$pid"]="$cmd"
        done < <(ps aux | grep -i "${target_process}" | grep -v "grep")

        # Send SIGTERM to the processes
        for pid in "${!pid_command_map[@]}"; do
            cmd="${pid_command_map[$pid]}"
            truncated_cmd=$(echo "$cmd" | awk -F/ '{n=NF; print $(n-2) "/" $(n-1) "/" $n}')
            echo "Attempting graceful shutdown: $target_process - $pid ($truncated_cmd)"
            kill -15 "$pid"
        done

        # Wait for 2 seconds if there are any processes
        if [ ${#pid_command_map[@]} -gt 0 ]; then
            sleep 2
        fi

        # Check if the processes are still running, and if so, send SIGKILL
        for pid in "${!pid_command_map[@]}"; do
            cmd="${pid_command_map[$pid]}"
            truncated_cmd=$(echo "$cmd" | awk -F/ '{n=NF; print $(n-2) "/" $(n-1) "/" $n}')
            if ps -p "$pid" > /dev/null; then
                echo "Having to kill: $target_process - $pid ($truncated_cmd)"
                kill -9 "$pid"
            fi
        done

        # Clear the pid_command_map associative array
        unset pid_command_map
        declare -A pid_command_map
    done
}

alias youdosser='find . -type f -exec dos2unix {} \;'

function apt_upgrader() {
	sudo apt update -y
	sudo apt upgrade -y
	sudo apt-get update -y
	sudo apt-get upgrade -y
    sudo apt full-upgrade -y
    sudo apt autoremove -y
}

# Python
function pypath() {
	export PYTHONPATH=$(pwd)/src:$(pwd)/tests:$PYTHONPATH;
	IFS=:
	unique_paths=()
	for path in $PYTHONPATH; do
	    if [[ ! "${unique_paths[*]}" =~ ${path} ]]; then
		unique_paths+=("$path")
	    fi
	done
	IFS=$' \t\n'

	new_path=$(IFS=:; echo "${unique_paths[*]}")
	export PYTHONPATH="$new_path"
	ppypath
}

function enter_pyenv() {
    if [ -z "$1" ]; then
        expected_env_name="$(basename $(pwd))"
    else
        expected_env_name="$1"
    fi
    echo "Activating: $expected_env_name"
    # Check if the virtual environment exists
    if [[ "$(pyenv versions --bare | grep -x $expected_env_name)" != "" ]]; then
      echo "Virtual environment '$expected_env_name' exists, activating it..."
      pyenv activate $expected_env_name
    else
      echo "Virtual environment '$expected_env_name' does not exist, creating it..."
      pyenv virtualenv $expected_env_name
      pyenv activate $expected_env_name
    fi
}

function pylint() {
    # Check if we're in a virtual environment
    if [ -z "${VIRTUAL_ENV}" ]; then
        echo "Not in a virtual environment. Activating..."
        enter_pyenv
    fi
    pip install -U black isort ruff
    isort --profile black .
    black -t py311 .
    ruff --fix .
}

function pipcompiler() {
    # Check if we're in a virtual environment
    if [ -z "${VIRTUAL_ENV}" ]; then
        echo "Not in a virtual environment. Activating..."
        enter_pyenv
    fi
    
    # Confirm the activation worked..
    if [ -z "${VIRTUAL_ENV}" ]; then
        echo "Not in a virtual environment. Please activate a virtual environment and try again."
        exit 1
    fi

    echo "Running pip compiler"
    pip install -U pip pip-tools

    # Find .in files in the current directory or in requirements/ directory
    if ls requirements*.in &> /dev/null; then
        files=$(ls *.in | grep '^requirements.*in' | sort -V)
    else
        files=$(ls requirements/*.in | grep 'requirements*' | sort -V)
    fi

    echo "Requirements files:"
    echo "${files}"
    # If no files were found, exit
    if [ -z "${files}" ]; then
        echo "No requirements*.in files found."
        return 1
    fi

    # Pip-compile each .in file
    for file in ${files}; do
        echo "Compiling ${file}"
	cat -s ${file} > tmp.txt && mv tmp.txt ${file}
	(awk '/^--/' ${file}; awk '!/^--/' ${file} | sort) | sponge ${file}
	rm -f "${file//.in/.txt}"
        pip-compile --resolver=backtracking "${file}"
    done

    # Find .txt files generated by pip-compile
    txt_files=$(echo "${files}" | sed 's/\.in/.txt/g')
    echo "Generated requirements*.txt files: ${txt_files}"
    
    # Build pip install command with each .txt file
    install_command="pip install"
    for txt_file in ${txt_files}; do
        install_command+=" -r ${txt_file}"
    done

    # Execute the pip install command
    echo "Executing: ${install_command}"
    ${install_command}
}

function version_bumper() {
    gitthefuckout && pipcompiler && git cam 'bump reqs' &&  git push origin main:bump_reqs
}             

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
    git fetch origin && git reset --hard origin/main && git checkout main
  else
    git fetch origin && git reset --hard origin/master && git checkout master
  fi
  git pull
}

function attackoftheclones() {
   # Get the organization name from the function argument or basename of dir
    if [ -z "$1" ]; then
        ORG_NAME="$(basename $(pwd))"
    else
        ORG_NAME="$1"
    fi

    # Clone or pull each repository
    for REPO_NAME in $(gh repo list "${ORG_NAME}" --json=name --limit 1000 | jq -r '.[].name'); do
        echo "Checking: $REPO_NAME"
        if [ -d "$REPO_NAME" ]; then
            echo "Repository already exists: $REPO_NAME"
            cd "$REPO_NAME"
            gitthefuckout
            cd ..
        else
            echo "Cloning repository: ${ORG_NAME}/${REPO_NAME}"
            gh repo clone ${ORG_NAME}/${REPO_NAME}
        fi
    done
}

alias multipull="find . -mindepth 1 -maxdepth 1 -type d -print -exec git -C {} pull \;"

##
#K8s
##
alias k9s="k9s-nsg"
##
#Docker
##
alias dockoff='docker rm -vf $(docker ps -aq); docker rmi -f $(docker images -aq); docker system prune -f; docker network create main'
alias dockeredo='docker compose down -v && docker network create main && docker compose up -d --remove-orphans'
alias dockercontainers='docker ps --format="table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" | (read -r; printf "%s\n" "$REPLY"; sort -k 2,2 -k 1,1 )'

function dockerperv() {
   sleep_time_secs=2
    while true; do
        clear
        echo "Every $sleep_time_secs s: dockercontainers: $(date)"
        dockercontainers
        sleep $sleep_time_secs
    done
}

##
#vpn
##
function start_vpn {
  pushd ~/vpn > /dev/null
  source ./start_vpn.sh
  popd > /dev/null
}
