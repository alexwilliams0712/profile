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

print_function_name() {
    echo -e "\033[1;36mExecuting function: ${FUNCNAME[1]}\033[0m"
}

# Grep and Tail fix logs easily by placing a separator bewtween fields
function grepcfix() {
   \grep --color=always $@ | sed 's/\x1/|/g'
}

function tailfix() {
   \tail -f  $@ | sed 's/\x1/|/g'
}

function murder() {
    print_function_name
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
            sudo kill -15 "$pid"
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
                sudo kill -9 "$pid"
            fi
        done

        # Clear the pid_command_map associative array
        unset pid_command_map
        declare -A pid_command_map
    done
}

alias youdosser='find . -type f -exec dos2unix {} \;'

function apt_upgrader() {
	print_function_name
    sudo systemctl stop packagekit
	sudo apt update -y
	sudo apt upgrade -y
	sudo apt full-upgrade -y
	sudo apt autoremove -y
	sudo apt-get -o DPkg::Lock::Timeout=-1 update -y
	sudo apt-get -o DPkg::Lock::Timeout=-1 upgrade -y
    sudo systemctl start packagekit
}

# Rust
function clippy() {
    local current_toolchain=$(rustup show active-toolchain | cut -d '-' -f1)
	echo "Current toolchain: $current_toolchain"
    cargo +stable clippy --fix
    cargo +nightly fmt
    rustup default "$current_toolchain"
    echo "Switched back to $current_toolchain toolchain"
    git status
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
	IFS=:; for i in $PYTHONPATH; do echo $i; done; unset IFS
}

function enter_pyenv() {
    print_function_name
    # if [ -z "$1" ]; then
    #     expected_env_name="$(basename $(pwd))"
    # else
    #     expected_env_name="$1"
    # fi
    # echo "Activating: $expected_env_name"
    # # Check if the virtual environment exists
    # if [[ "$(pyenv versions --bare | grep -x $expected_env_name)" != "" ]]; then
    #   echo "Virtual environment '$expected_env_name' exists, activating it..."
    #   pyenv activate $expected_env_name
    # else
    #   echo "Virtual environment '$expected_env_name' does not exist, creating it..."
    #   pyenv virtualenv $expected_env_name
    #   pyenv activate $expected_env_name
    # fi

    if [ ! -d ".venv" ]; then
        # If it does not exist, create the virtual environment
         uv venv
    fi

    # Activate the virtual environment
    source .venv/bin/activate
    pypath
}

function pylint() {
    print_function_name
    # Check if we're in a virtual environment
    if [ -z "${VIRTUAL_ENV}" ]; then
        echo "Not in a virtual environment. Activating..."
        enter_pyenv
    fi
    uv pip install -U black isort ruff

    isort --profile black --skip __init__.py .
    black -t py311 .
    ruff check --fix .
}


function pipcompiler() {
    print_function_name
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
    uv pip install -U pip pip-tools

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
        (grep "^-" ${file}; grep -v "^-" ${file} | sort) | sponge ${file}
        rm -f "${file//.in/.txt}"
        uv pip compile "${file}"
    done

    # Find .txt files generated by pip-compile
    txt_files=$(echo "${files}" | sed 's/\.in/.txt/g')
    echo "Generated requirements*.txt files: ${txt_files}"

    # Build pip install command with each .txt file
    install_command="uv pip sync"
    for txt_file in ${txt_files}; do
        install_command+=" ${txt_file}"
    done

    # Execute the pip install command
    echo -e "\033[1;33mExecuting: ${install_command}\033[0m"
    ${install_command}
}

function new_pr() {
    if [[ $# -eq 0 ]] || [[ $1 =~ [[:space:]] ]]; then
        echo "Error: Argument required with no spaces."
        return 1
    fi
    if [[ -z $(git status --porcelain) ]]; then
        echo "No changes to commit"
        return
    fi

    local branch_name=$1
    
    git checkout -b $branch_name
    git cam "$branch_name"
    git push --set-upstream origin "$branch_name"
    gh pr create --base main --head "$branch_name" --title "$branch_name" --body "$branch_name"
}

function version_bumper() {
    print_function_name
    gitthefuckout
    pipcompiler
    new_pr bump_reqs
}

function multi_version_bumper() {
    for dir in "$@"; do
        if [ -d "$dir" ]; then
            echo "Entering directory: $dir"
            cd "$dir"
            enter_pyenv
            version_bumper
            cd ..
            pyenv deactivate
            echo "Exited directory: $dir"
        else
            echo "Directory not found: $dir"
        fi
    done
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
    print_function_name
    git ls-remote --exit-code --heads origin main >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        git fetch origin && git reset --hard origin/main && git checkout main
    else
        git fetch origin && git reset --hard origin/master && git checkout master
    fi
    git pull
}

function attackoftheclones() {
    print_function_name
   # Get the organization name from the function argument or basename of dir
    if [ -z "$1" ]; then
        ORG_NAME="$(basename $(pwd))"
    else
        ORG_NAME="$1"
    fi

    # Clone or pull each repository
    for REPO_NAME in $(gh repo list "${ORG_NAME}" --json=name --limit 1000 | jq -r '.[].name'); do
	echo -e "\033[1;33mChecking: ${REPO_NAME}\033[0m"
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

function git_https_to_ssh() {
  # Get the fetch URL
  url=$(git remote -v | grep fetch | awk '{print $2}')

  # Check if it's an HTTPS URL
  if [[ $url != https://* ]]; then
    echo "Remote origin is not an HTTPS URL. No change made."
    return 1
  fi

  # Convert the HTTPS URL to SSH format
  ssh_url="git@${url#https://}"
  ssh_url="${ssh_url/\//:}"
  ssh_url="${ssh_url/\/.git/.git}"

  # Set the new URL
  git remote set-url origin $ssh_url

  echo "Origin URL successfully changed to SSH format:"
  git remote -v
}

##
#K8s
##
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
function kube_ghcr_secret() {
  if [ "$#" -ne 1 ]; then
    echo "Usage: kube_secret <namespace>"
    return 1
  fi
  local namespace="$1"
  if ! kubectl get namespace "$namespace" > /dev/null 2>&1; then
    echo "Namespace '$namespace' does not exist. Creating it..."
    kubectl create namespace "$namespace"
  fi
  kubectl create secret docker-registry ghcr-credentials \
    --docker-server=https://ghcr.io \
    --docker-username="$(git config --global user.name)" \
    --docker-password="$(gh auth token)" \
    -n "$namespace"
}
alias helm_launch='helm template helm/ | kubectl apply -f -'
alias helm_kill='helm template helm/ | kubectl delete -f -'
##
#Docker
##

function postgres_docker_reset() {
	sudo apt-get install bridge-utils
	sudo pkill docker
	sudo iptables -t nat -F
	sudo ifconfig docker0 down
	sudo brctl delbr docker0
	sudo service docker restart
}

function ghcr_docker_login() {
    print_function_name
    if [ -z "$1" ]
    then
        echo "No username supplied!"
        return 1
    fi

    local USERNAME=$1
    local GH_TOKEN=$(gh auth token)
    if [ -z "$GH_TOKEN" ]
    then
        echo "No token available from 'gh auth token'!"
        return 1
    fi
    echo $GH_TOKEN | docker login ghcr.io -u $USERNAME --password-stdin
}
function dockeredo() {
    print_function_name
    local NETWORK_NAME="main"
    docker compose down -v

    if ! docker network ls | grep -q " $NETWORK_NAME "; then
        docker network create $NETWORK_NAME
    fi
    docker compose up -d --remove-orphans
}
alias dockill='docker rm -vf $(docker ps -aq)'
alias dockoff='dockill; docker rmi -f $(docker images -aq); docker system prune -f; docker network create main'
alias dockercontainers='docker ps --format="table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" | (read -r; printf "%s\n" "$REPLY"; sort -k 2,2 -k 1,1 )'

dockerperv () {
    print_function_name
    sleep_time_secs=2
    sort_option="-k 2,2 -k 1,1"
    if [ "$1" ]; then
        case "$(echo "$1" | tr '[:upper:]' '[:lower:]')" in
            name)
                sort_option="-k 1,1 -k 2,2"
                ;;
            image)
                sort_option="-k 2,2 -k 1,1"
                ;;
            *)
                echo "Invalid argument. Sorting by default (image)."
                ;;
        esac
    fi
    while true; do
        clear
        echo "Every $sleep_time_secs s: dockercontainers: $(date)"
        docker ps --format="table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" | ( read -r; printf "%s\n" "$REPLY"; sort $sort_option )
        sleep $sleep_time_secs
    done
}


function dockerbuild() {
    print_function_name
    sleep_time_secs=2
    print_function_name
    if [ -z "$1" ]
    then
        echo "No tag supplied!"
        return 1
    fi
    local NEW_TAG=$1
    if [[ ! -f ~/.packagr_details ]]; then
        echo "Error: File ~/.packagr_details does not exist!"
        return 1
    fi
    docker build -t $NEW_TAG --target runtime --secret id=env,src=~/.packagr_details .
    docker image push $NEW_TAG
}

##
# AWS
##
function ecsclusters() {
    clusters=$(aws ecs list-clusters --output json | jq -r '.clusterArns[]')
    declare -a cluster_info

    for cluster in $clusters; do
        cluster_name=$(echo $cluster | rev | cut -d'/' -f1 | rev)
        if [[ -z "$1" ]] || [[ $cluster_name == *$1* ]]; then
            task_counts=$(aws ecs describe-clusters --clusters $cluster --output json --query 'clusters[0].{runningTasksCount:runningTasksCount, pendingTasksCount:pendingTasksCount}')
            running_tasks=$(echo $task_counts | jq -r '.runningTasksCount')
            pending_tasks=$(echo $task_counts | jq -r '.pendingTasksCount')
            cluster_info+=("$cluster_name $running_tasks $pending_tasks")
        fi
    done

    # Print the table header with borders
    printf "+--------------------------------------------------+---------------+---------------+\n"
    printf "| %-48s | %-13s | %-13s |\n" "ClusterName" "RunningTasks" "PendingTasks"
    printf "+--------------------------------------------------+---------------+---------------+\n"

    # Print each row of the table
    for info in "${cluster_info[@]}"; do
        printf "| %-48s | %-13s | %-13s |\n" $info
    done | sort

    # Bottom border of the table
    printf "+--------------------------------------------------+---------------+---------------+\n"
}


function awsperv() {
    watch -n 10 -x bash -ic "ecsclusters $1"
}

function ssh_aws_dublin() {
    ssh -i ~/.ssh/aws_key_dublin.pem ec2-user@"$1"
}

function ssh_aws_tokyo() {
    ssh -i ~/.ssh/aws_key_tokyo.pem ec2-user@"$1"
}


##
#vpn
##
function start_vpn {
    print_function_name
    pushd ~/vpn > /dev/null
    source ./start_vpn.sh
    popd > /dev/null
}
