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
alias ls='lsd -F'
alias l='ls -c'                 # show most recent files first
alias la='ls -A'                # show all (including '.files', exluding ./ and ../)
alias ll='ls -lAh'              # show all as a list sorted alphabetically
alias llf='ll | grep -vE "^d"'  # ll files only
alias lt='ls -lArth'            # show all as a list sorted by reversed modification time

##
# CAT ALIASES
##
alias bat='batcat'


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

function log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S.%3N') - $1"
}

# Grep and Tail fix logs easily by placing a separator bewtween fields
function grepcfix() {
   \grep --color=always $@ | sed 's/\x1/|/g'
}

function tailfix() {
   \tail -f  $@ | sed 's/\x1/|/g'
}

function scp_mirror() {
    # $ scp_mirror alex-work ~/.aws ~/vpn ~/.netrc ~/.personal ~/.cargo/credentials.toml
    if [ $# -lt 2 ]; then
        log "Usage: scp_mirror remote_host dir1 [dir2 ...]"
        return 1
    fi

    local host="$1"
    shift  # Remove the host argument, leaving only the directory list

    for dir in "$@"; do
        # Expand the ~ to $HOME if present
        local expanded_dir="${dir/#\~/$HOME}"
        log "Copying $host:$dir to $expanded_dir"
        # Create the parent directory if it doesn't exist
        mkdir -p "$(dirname "$expanded_dir")"
        scp -r "$host:$dir" "$expanded_dir"
    done
}


function murder() {
    print_function_name
    if [ "$#" -eq 0 ]; then
        echo "Error: Please provide at least one process name."
        return 1
    fi
    sudo -v
    for target_process in "$@"; do
        # Attempt graceful shutdown first
        log "$target_process - Attempting to kill"
        sudo pkill -15 -f "$target_process" 2>/dev/null || echo "No matching processes found for SIGTERM."

        # Wait for processes to terminate
        sleep 2

        # Check if any processes are still running and forcefully terminate them
        if pgrep -f "$target_process" > /dev/null 2>&1; then
            log "$target_process - Some processes are still running. Forcing shutdown (SIGKILL)"
            sudo pkill -9 -f "$target_process" 2>/dev/null || echo "Failed to kill remaining processes."
        else
            log "$target_process - Processes terminated gracefully."
        fi
    done
}


kill_on_port() {
  if [ -z "$1" ]; then
    log "Please provide a port number."
    return 1
  fi

  PORT=$1
  # Find the PID of the process using the port
  PID=$(lsof -t -i:"$PORT")

  if [ -z "$PID" ]; then
    log "No process found running on port $PORT."
  else
    # Kill the process
    kill -9 $PID
    log "Killed process $PID running on port $PORT."
  fi
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

alias file_counter="find . -maxdepth 1 -type f | sed -n 's/..*\.//p' | sort | uniq -c"

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
        uv venv -p $(pyenv global)
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

    isort --profile black --skip __init__.py --skip .venv .
    black .
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
        uv pip compile "${file}" -o ${file//.in/.txt} --emit-index-url
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

function pyspy_profile() {
    local app_name="$1"
    if [ -z "$app_name" ]; then
        echo "Usage: pyspy_profile <app_name>"
        return 1
    fi
    
    local pid=$(ps aux | grep "[${app_name:0:1}]${app_name:1}" | awk '{print $2}')
    if [ -z "$pid" ]; then
        echo "No process found matching '$app_name'"
        return 1
    fi
    
    local output_file="${app_name}_profile.svg"
    
    echo "Profiling process '$app_name' (PID: $pid)"
    sudo env "PATH=$PATH" py-spy record -o "$output_file" --pid "$pid"
    
    echo "Profile saved to $output_file"
}

function new_pr() {
    if [[ $# -eq 0 ]] || [[ $1 =~ [[:space:]] ]]; then
        echo "Error: Argument required with no spaces."
        return 1
    fi

    local branch_name=$1
    if git show-ref --verify --quiet "refs/heads/$branch_name"; then
        echo "Branch '$branch_name' already exists locally."
        git checkout "$branch_name"
    else
        git checkout -b "$branch_name"
    fi
    if [[ -z $(git status --porcelain) ]]; then
        echo "No changes detected. Creating an empty commit if nothing is pushed yet."
        if [[ -z $(git log origin/"$branch_name" 2>/dev/null) ]]; then
            git commit --allow-empty -m "$branch_name"
        fi
    else
        echo "Changes detected. Adding and committing."
        git add .
        git commit -m "$branch_name"
    fi
    git push --set-upstream origin "$branch_name"
    if gh pr view --head "$branch_name" &>/dev/null; then
        echo "Pull request for branch '$branch_name' already exists. Opening it."
        gh pr view --web --head "$branch_name"
    else
        echo "Creating a new pull request for branch '$branch_name'."
        gh pr create --base main --head "$branch_name" --title "$branch_name" --body "$branch_name"
    fi
}


function version_bumper() {
    print_function_name
    gitthefuckout
    pipcompiler
    uuid=$(uuidgen)
    new_pr "bump_reqs_${uuid}"
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

function mkdir_cd() {
    if [ -z "$1" ]; then
        echo "Error: No directory path supplied."
        return 1
    fi
    
    mkdir -p "$1" && cd "$1"
}

##
#git
##
alias git_compress="git gc --aggressive --prune=now"

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

function remove_offline_runners() {
    local ORG_NAME=$1
    local SLEEP_TIME=${2:-0.5}  # Optional: second argument for sleep time, default is 0.5 seconds
    
    while true; do
        # Fetch all runners, handle pagination
        runners=$(gh api -X GET /orgs/$ORG_NAME/actions/runners --paginate)

        # Parse and filter offline runners
        offline_runners=$(echo "$runners" | jq -r '.runners[] | select(.status == "offline") | .id')

        # Check if there are no more offline runners
        if [ -z "$offline_runners" ]; then
            log "No more offline runners to remove."
            break
        fi

        # Loop through and remove each offline runner
        for runner_id in $offline_runners; do
            log "Removing offline runner with ID: $runner_id"
            gh api -X DELETE /orgs/$ORG_NAME/actions/runners/$runner_id
            sleep $SLEEP_TIME
        done

        log "Cycle complete, checking for more offline runners..."
    done

    log "All offline runners removed."
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

docker_build_with_creds() {
    print_function_name
    local image_name="$(basename "$PWD" | tr '-' '_')"
    local target="runtime"
    local dockerfile="Dockerfile"
    local netrc_file="$HOME/.netrc"
    local cargo_credentials_file="$HOME/.cargo/credentials.toml"
    local temp_secrets_file=$(mktemp)

    # Parse named arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --image-name)
                image_name="$2"
                shift 2
                ;;
            --target)
                target="$2"
                shift 2
                ;;
            --dockerfile)
                dockerfile="$2"
                shift 2
                ;;
            --netrc)
                netrc_file="$2"
                shift 2
                ;;
            --cargo_credentials)
                cargo_credentials_file="$2"
                shift 2
                ;;
            *)
                echo "Unknown option: $1"
                return 1
                ;;
        esac
    done

    # Extract username and password from .netrc
    local username=$(awk '/machine api.packagr.app/ {print $4}' "$netrc_file")
    local password=$(awk '/machine api.packagr.app/ {print $6}' "$netrc_file")

    # Extract the SHIPYARD_TOKEN from credentials.toml
    local shipyard_token=$(grep -A1 '^\[registries\.' "$cargo_credentials_file" | grep 'token' | sed -E 's/token = "(.*)"/\1/')

    # Create temporary secrets file
    echo "PACKAGR_USERNAME=$username" > "$temp_secrets_file"
    echo "PACKAGR_PASSWORD=$password" >> "$temp_secrets_file"
    echo "SHIPYARD_TOKEN=$shipyard_token" >> "$temp_secrets_file"
    echo "SSH_PRIVATE_KEY=$(cat ~/.ssh/id_ed25519 | base64 | tr -d '\n')" >> "$temp_secrets_file"

    # Build Docker image
    local build_command="DOCKER_BUILDKIT=1 docker build \
        --secret id=env,src=\"$temp_secrets_file\" \
        -t \"$image_name\" \
        -f \"$dockerfile\""

    # Add target if specified
    if [[ -n "$target" ]]; then
        build_command+=" --target \"$target\""
    fi

    build_command+=" ."

    eval $build_command

    # Remove temporary secrets file
    rm "$temp_secrets_file"

    echo "Docker image $image_name built successfully."
}


function copy_to_k3s() {
    local image_name=$1

  if [ -z "$image_name" ]; then
    echo "Usage: import_image_to_k3s <image_name:tag>"
    return 1
  fi

  echo "Saving Docker image $image_name..."
  docker save "$image_name" | sudo k3s ctr images import -

  if [ $? -ne 0 ]; then
    echo "Failed to import the image into k3s."
    return 1
  fi

  echo "Image $image_name successfully imported into k3s."
  echo "Listing the imported image in k3s..."
  sudo k3s ctr images ls | grep "$image_name"
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


function ssh_aws() {
    if [ -z "$1" ] || [ -z "$2" ]; then
        echo "Usage: ssh_aws <region> <host>"
        return 1
    fi
    
    region="$1"
    host="$2"
    pem_file="~/.ssh/aws_key_${region}.pem"

    if [ ! -f "${pem_file/#\~/$HOME}" ]; then
        echo "PEM file for region $region does not exist: $pem_file"
        return 1
    fi

    ssh -i "${pem_file}" ec2-user@"$host"
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


# Fun
function laughing_at_idiots() {
    # sudo apt-get install -y fswebcam imagemagick
    ((
        insults=( \
            "MASSIVE FUCKING MORON" \
            "YOU FOOL" \
            "HAHA HACKED YA" \
        )
        random_index=$((RANDOM % ${#insults[@]}))
        random_insult="${insults[$random_index]}"

        filepath="/tmp/mug.jpeg"
        fswebcam -r 1080x1920 --skip 100 $filepath > /dev/null 2>&1 
        convert $filepath -gravity North -pointsize 72 -fill red -annotate 0 "${random_insult}" $filepath > /dev/null 2>&1 
        eog -f $filepath > /dev/null 2>&1
    ) > /dev/null 2>&1 & disown)
}
