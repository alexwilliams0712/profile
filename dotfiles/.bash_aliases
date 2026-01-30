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
alias l='ls -c'                # show most recent files first
alias la='ls -A'               # show all (including '.files', exluding ./ and ../)
alias ll='ls -lAh'             # show all as a list sorted alphabetically
alias llf='ll | grep -vE "^d"' # ll files only
alias lt='ls -lArth'           # show all as a list sorted by reversed modification time

##
# CAT ALIASES
##
if command -v batcat >/dev/null 2>&1; then
	alias bat='batcat'
fi

##
# CD ALIASES
##
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias bk='cd $OLDPWD'
alias ppath='IFS=:; for i in $PATH; do echo $i; done; unset IFS'

print_function_name() {
	log "\033[1;36mExecuting function: ${FUNCNAME[1]}\033[0m"
}

alias ubuntu='lsb_release -a'

function log() {
	echo -e "$(date '+%Y-%m-%d %H:%M:%S.%3N') - $1"
}

# Grep and Tail fix logs easily by placing a separator bewtween fields
function grepcfix() {
	\grep --color=always $@ | sed 's/\x1/|/g'
}

function tailfix() {
	\tail -f $@ | sed 's/\x1/|/g'
}

function scp_mirror() {
	# Usage
	# $ scp_mirror alex-home ~/.netrc ~/vpn/ ~/.aws ~/.personal ~/.packagr_details
	if [ $# -lt 2 ]; then
		echo "Usage: scp_mirror remote_host path1 [path2 ...]"
		return 1
	fi

	local host="$1"
	shift
	local owner="${SUDO_USER:-$USER}"

	for path in "$@"; do
		# Expand tilde for local destination
		local local_path="${path/#\~/$HOME}"
		# Normalize remote path (leave ~ intact for remote shell)
		local remote_path="${path}"

		# Ensure local parent exists
		mkdir -p "$(dirname "$local_path")"

		# If path ends with a slash, treat it as directory: copy contents only
		if [[ "$path" == */ ]]; then
			echo "Copying contents of $host:$remote_path to $local_path"
			sudo scp -r $host:${remote_path%/}/* $local_path
		else
			echo "Copying $host:$remote_path to $local_path"
			sudo scp -r $host:$remote_path $local_path
		fi
		sudo chown -R "$owner":"$owner" "$local_path"
		sudo chmod -R u+rwX "$local_path"
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
		# Count matching processes before SIGTERM (case-insensitive)
		initial_count=$(pgrep -fi "$target_process" | wc -l)
		if [ "$initial_count" -eq 0 ]; then
			log "No matching processes found for $target_process."
			continue
		fi

		log "$target_process - Attempting graceful shutdown (SIGTERM) of $initial_count processes"
		sudo pkill -15 -fi "$target_process" 2>/dev/null

		# Wait for processes to terminate
		sleep 2

		# Count remaining
		remaining_count=$(pgrep -fi "$target_process" | wc -l)
		killed_count=$((initial_count - remaining_count))

		if [ "$remaining_count" -gt 0 ]; then
			log "$target_process - $killed_count terminated with SIGTERM, $remaining_count remaining. Forcing shutdown (SIGKILL)"
			sudo pkill -9 -fi "$target_process" 2>/dev/null
			sleep 1
			final_remaining=$(pgrep -fi "$target_process" | wc -l)
			force_killed=$((remaining_count - final_remaining))
			log "$target_process - $force_killed forcibly killed with SIGKILL. $final_remaining may still remain."
		else
			log "$target_process - All $initial_count processes terminated gracefully with SIGTERM."
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

clean_broken_repos() {
	local update_output
	local repo_urls=()

	# Capture apt update output
	update_output=$(sudo apt update 2>&1)
	echo "$update_output"

	# Extract repository URLs that have missing Release files
	while IFS= read -r line; do
		if [[ $line =~ "does not have a Release file" ]]; then
			# Extract the repository URL from the previous error line
			local prev_line=$(echo "$update_output" | grep -B1 "does not have a Release file" | grep "Error:" | tail -1)
			if [[ $prev_line =~ https?://[^[:space:]]+ ]]; then
				local repo_url="${BASH_REMATCH[0]}"
				repo_urls+=("$repo_url")
			fi
		fi
	done <<<"$update_output"

	# Auto-remove .list files for broken repositories
	if [ ${#repo_urls[@]} -gt 0 ]; then
		echo -e "\n🔍 Found ${#repo_urls[@]} broken repository(ies). Auto-removing corresponding .list files..."

		for repo_url in "${repo_urls[@]}"; do
			echo "Processing: $repo_url"

			# Extract domain/path components for matching
			local domain=$(echo "$repo_url" | sed 's|https\?://||' | cut -d'/' -f1)

			# Find matching .list files
			local list_files=$(find /etc/apt/sources.list.d/ -name "*.list" -exec grep -l "$domain" {} \; 2>/dev/null)

			if [ -n "$list_files" ]; then
				echo "Found and removing matching .list file(s):"
				echo "$list_files" | while read -r file; do
					echo "  📁 $file"
					sudo rm "$file"
					echo "  ✅ Removed: $file"
				done
			else
				echo "  ❌ No matching .list file found for $domain"
			fi
		done

		echo -e "\n🔄 Running apt update again..."
		sudo apt update
	else
		echo -e "\n✅ No broken repositories found."
	fi
}

function apt_upgrader() {
	print_function_name
	sudo find /etc/apt/sources.list.d/ -name "*.sources" -exec grep -l questing {} \; -exec rm -v {} \;
	sudo systemctl stop packagekit
	clean_broken_repos
	sudo apt update -y
	sudo apt upgrade -y
	sudo apt full-upgrade -y
	sudo apt autoremove -y
	sudo apt-get -o DPkg::Lock::Timeout=-1 update -y
	sudo apt-get -o DPkg::Lock::Timeout=-1 upgrade -y
	sudo systemctl start packagekit
}

alias file_counter="find . -maxdepth 1 -type f | sed -n 's/..*\.//p' | sort | uniq -c"

filecount_table() {
	# Default to current directory if no argument provided
	local search_dir="${1:-.}"

	# Get all unique file extensions
	local all_extensions=$(find "$search_dir" -type f | awk -F. '{print $NF}' | tr '[:upper:]' '[:lower:]' | sort -u)

	# Create arrays to store column widths
	declare -A max_width
	max_width["dir"]=9 # "Directory" has 9 characters

	# Initialize extension widths
	for ext in $all_extensions; do
		max_width["$ext"]=${#ext}
	done

	# Find the maximum width needed for each directory name
	while read dir; do
		dir_name=$(echo "$dir" | sed "s|^$search_dir/||")
		if [ ${#dir_name} -gt ${max_width["dir"]} ]; then
			max_width["dir"]=${#dir_name}
		fi
	done < <(find "$search_dir" -mindepth 1 -type d | sort)

	# Find the maximum width needed for each count
	for ext in $all_extensions; do
		while read dir; do
			count=$(find "$dir" -maxdepth 1 -type f -name "*.$ext" -o -name "*.$(echo $ext | tr '[:lower:]' '[:upper:]')" | wc -l)
			if [ ${#count} -gt ${max_width["$ext"]} ]; then
				max_width["$ext"]=${#count}
			fi
		done < <(find "$search_dir" -mindepth 1 -type d | sort)
	done

	# Print table header with proper padding
	printf "| %-${max_width["dir"]}s " "Directory"
	for ext in $all_extensions; do
		printf "| %-${max_width["$ext"]}s " "$ext"
	done
	echo "|"

	# Print header separator with proper width
	printf "| %s " "$(printf '%0.s-' $(seq 1 ${max_width["dir"]}))"
	for ext in $all_extensions; do
		printf "| %s " "$(printf '%0.s-' $(seq 1 ${max_width["$ext"]}))"
	done
	echo "|"

	# For each subdirectory
	find "$search_dir" -mindepth 1 -type d | sort | while read dir; do
		# Print directory name without the search_dir prefix
		dir_name=$(echo "$dir" | sed "s|^$search_dir/||")
		printf "| %-${max_width["dir"]}s " "$dir_name"

		# For each extension, count files in this directory
		for ext in $all_extensions; do
			count=$(find "$dir" -maxdepth 1 -type f -name "*.$ext" -o -name "*.$(echo $ext | tr '[:lower:]' '[:upper:]')" | wc -l)
			printf "| %-${max_width["$ext"]}s " "$count"
		done
		echo "|"
	done
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

function diesel_setup() {
	# Load .env if it exists
	[[ -f .env ]] && export $(grep -v '^#' .env | xargs)

	# Check DATABASE_URL
	if [[ "$DATABASE_URL" == *"localhost"* ]]; then
		diesel migration redo && diesel database reset && cargo +nightly fmt
	else
		echo "🚫 DATABASE_URL does not contain 'localhost'. Aborting."
		return 1
	fi
}

# Python
function pypath() {
	export PYTHONPATH=$(pwd)/src:$(pwd)/tests:$PYTHONPATH
	IFS=:
	unique_paths=()
	for path in $PYTHONPATH; do
		if [[ ! "${unique_paths[*]}" =~ ${path} ]]; then
			unique_paths+=("$path")
		fi
	done
	IFS=$' \t\n'

	new_path=$(
		IFS=:
		echo "${unique_paths[*]}"
	)
	export PYTHONPATH="$new_path"
	IFS=:
	for i in $PYTHONPATH; do echo $i; done
	unset IFS
}

function _select_option() {
	local prompt="$1"
	shift
	local options=("$@")
	local selected=0
	local count=${#options[@]}
	local esc=$(printf '\033')

	echo "$prompt"
	echo "Use ↑/↓ arrows, Enter to select"
	echo ""

	# Hide cursor and save position
	printf '\033[?25l'

	while true; do
		# Print menu
		for i in "${!options[@]}"; do
			if [ $i -eq $selected ]; then
				printf '\033[1;32m> %s\033[0m\n' "${options[$i]}"
			else
				printf '  %s\n' "${options[$i]}"
			fi
		done

		# Read single keypress
		IFS= read -rsn1 key

		# Check for escape sequence (arrow keys)
		if [[ $key == "$esc" ]]; then
			read -rsn2 -t 0.1 rest
			key+="$rest"
		fi

		# Handle key
		case "$key" in
		"${esc}[A") # Up
			((selected--))
			((selected < 0)) && selected=$((count - 1))
			;;
		"${esc}[B") # Down
			((selected++))
			((selected >= count)) && selected=0
			;;
		"") # Enter
			break
			;;
		esac

		# Move cursor back up to redraw
		printf '\033[%dA' "$count"
	done

	# Show cursor
	printf '\033[?25h'
	echo ""

	SELECTED_OPTION="${options[$selected]}"
}

function enter_pyenv() {
	print_function_name

	if [ ! -d ".venv" ]; then
		# Get available Python versions from pyenv (filter to version numbers only)
		local versions=($(pyenv versions --bare 2>/dev/null | grep -E '^[0-9]+\.[0-9]+' | sort -V -r))

		if [ ${#versions[@]} -eq 0 ]; then
			echo "No Python versions found in pyenv. Using system Python."
			uv venv
		else
			_select_option "Select Python version for new .venv:" "${versions[@]}"
			local selected_version="$SELECTED_OPTION"

			echo "Creating .venv with Python ${selected_version}..."
			uv venv -p "$selected_version"
		fi
	fi

	# Activate the virtual environment
	source .venv/bin/activate
	echo "Python version: $(python --version 2>&1)"
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

	# Check if pyproject.toml exists and has a dependencies section
	if [ -f "pyproject.toml" ] && grep -q '^dependencies\s*=' pyproject.toml; then
		echo "Found pyproject.toml with dependencies, syncing directly..."

		# Build uv sync command with upgrade flag and all extras
		local sync_cmd="uv sync -U --all-extras"

		# Check for dependency-groups (PEP 735 style)
		local dep_groups=$(grep -oP '(?<=^\[dependency-groups\.)[^\]]+' pyproject.toml 2>/dev/null || true)
		for group in ${dep_groups}; do
			echo "Including dependency group: ${group}"
			sync_cmd+=" --group ${group}"
		done

		echo -e "\033[1;33mExecuting: ${sync_cmd}\033[0m"
		eval ${sync_cmd}
		return 0
	else
		# Fall back to requirements/*.in files
		echo "No pyproject.toml found, looking for requirements*.in files..."
		uv pip install -U pip pip-tools

		# Find .in files in the current directory or in requirements/ directory
		if ls requirements*.in &>/dev/null; then
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
			cat -s ${file} >tmp.txt && mv tmp.txt ${file}
			(
				grep "^-" ${file}
				grep -v "^-" ${file} | sort
			) | sponge ${file}
			rm -f "${file//.in/.txt}"
			uv pip compile "${file}" -U -o ${file//.in/.txt}
		done

		# Find .txt files generated by pip-compile
		txt_files=$(echo "${files}" | sed 's/\.in/.txt/g')
		echo "Generated requirements*.txt files: ${txt_files}"
	fi

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

function empty_commit() {
	git commit --allow-empty -m "chore: trigger CI" && git push
}

function merge_main() {
	git pull
	git fetch origin
	git checkout main
	git pull origin main
	git checkout -
	git merge main
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
	local SLEEP_TIME=${2:-0.5} # Optional: second argument for sleep time, default is 0.5 seconds

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
	if ! kubectl get namespace "$namespace" >/dev/null 2>&1; then
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
	if [ -z "$1" ]; then
		echo "No username supplied!"
		return 1
	fi

	local USERNAME=$1
	local GH_TOKEN=$(gh auth token)
	if [ -z "$GH_TOKEN" ]; then
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

dockerperv() {
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
		docker ps --format="table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" | (
			read -r
			printf "%s\n" "$REPLY"
			sort $sort_option
		)
		sleep $sleep_time_secs
	done
}

function dockerbuild() {
	print_function_name
	sleep_time_secs=2
	print_function_name
	if [ -z "$1" ]; then
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
	echo "PACKAGR_USERNAME=$username" >"$temp_secrets_file"
	echo "PACKAGR_PASSWORD=$password" >>"$temp_secrets_file"
	echo "SHIPYARD_TOKEN=$shipyard_token" >>"$temp_secrets_file"
	echo "SSH_PRIVATE_KEY=$(cat ~/.ssh/id_ed25519 | base64 | tr -d '\n')" >>"$temp_secrets_file"

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
	pushd ~/vpn >/dev/null
	source ./start_vpn.sh
	popd >/dev/null
}

export JSON_LINE_WIDTH=180

# Formatters
# Set JSON_LINE_WIDTH to control max line width for simple arrays (default: 80)
formatter_json() {
	local line_width="${JSON_LINE_WIDTH:-80}"

	find . -type f \( -iname "*.json" -o -iname "*.json5" \) \
		-not -path "./.venv/*" -not -path "./target/*" | while read -r file; do
		log "Processing $file"

		ext="${file##*.}"

		# Convert json5 to json first if needed
		if [[ "$ext" == "json5" ]]; then
			json5 "$file" --out-file "$file"
		fi

		# Sort keys and align colons using Python
		python3 -c '
import json
import sys
import os

LINE_WIDTH = int(sys.argv[2])

def compact_json(obj):
    """Return compact JSON with sorted keys."""
    if isinstance(obj, dict):
        if not obj:
            return "{}"
        parts = []
        for k in sorted(obj.keys()):
            parts.append(f"{json.dumps(k)}: {compact_json(obj[k])}")
        return "{" + ", ".join(parts) + "}"
    elif isinstance(obj, list):
        if not obj:
            return "[]"
        return "[" + ", ".join(compact_json(x) for x in obj) + "]"
    else:
        return json.dumps(obj)

def align_json(obj, indent=0):
    ind = "  " * indent
    current_col = len(ind)

    if isinstance(obj, dict):
        if not obj:
            return "{}"
        # Try compact form first
        compact = compact_json(obj)
        if "\n" not in compact and current_col + len(compact) < LINE_WIDTH:
            return compact
        sorted_keys = sorted(obj.keys())
        max_len = max(len(json.dumps(k)) for k in sorted_keys)
        lines = ["{"]
        for i, key in enumerate(sorted_keys):
            key_str = json.dumps(key)
            value_str = align_json(obj[key], indent + 1)
            padding = " " * (max_len - len(key_str))
            comma = "," if i < len(sorted_keys) - 1 else ""
            lines.append(f"{ind}  {key_str}{padding}: {value_str}{comma}")
        lines.append(f"{ind}}}")
        return "\n".join(lines)
    elif isinstance(obj, list):
        if not obj:
            return "[]"
        # Try compact form first
        compact = compact_json(obj)
        if "\n" not in compact and current_col + len(compact) < LINE_WIDTH:
            return compact
        lines = ["["]
        for i, item in enumerate(obj):
            value_str = align_json(item, indent + 1)
            comma = "," if i < len(obj) - 1 else ""
            lines.append(f"{ind}  {value_str}{comma}")
        lines.append(f"{ind}]")
        return "\n".join(lines)
    else:
        return json.dumps(obj)

with open(sys.argv[1], "r") as f:
    data = json.load(f)
with open(sys.argv[1], "w") as f:
    f.write(align_json(data) + "\n")
' "$file" "$line_width" 2>/dev/null || {
			log "Failed to parse $file, falling back to jq"
			if command -v jq &>/dev/null; then
				jq -S '.' "$file" >"$file.tmp" && mv "$file.tmp" "$file"
			fi
		}
	done
}

formatter_sql() {
	find . -type f -iname "*.sql" \
		-not -path "./.venv/*" -not -path "./target/*" | while read -r file; do
		log "Processing $file"

		pg_format --keyword-case=2 --type-case=2 --comma-break --no-extra-line --inplace "$file"
	done
}

formatter_shell() {
	find . \
		-type f \
		\( -iname "*.sh" -o -name ".bashrc" -o -name ".bash_aliases" \) \
		-not -path "./.venv/*" \
		-not -path "./target/*" |
		while read -r file; do
			log "Processing $file"
			shfmt -l -w "$file"
		done
}

alias ti='terraform init'
alias tf='terraform fmt --recursive'
alias ta='terraform apply'

formatter() {
	formatter_json
	formatter_sql
	formatter_shell
	# Check for Python project
	if [ -f pyproject.toml ] || ls *.py &>/dev/null || [ -d .venv/ ]; then
		if [ -n "$VIRTUAL_ENV" ]; then
			log "Running pylint..."
			pylint $(find . -type f -name "*.py")
		else
			log "Python project detected, but not in a uv environment. Skipping pylint."
		fi
	fi

	# Check for Rust project
	if [ -f Cargo.toml ]; then
		if command -v cargo &>/dev/null; then
			log "Running cargo +nightly fmt..."
			cargo +nightly fmt
		else
			log "cargo not found. Skipping Rust formatting."
		fi
	fi

	# Terraform (terraform fmt)
	if find . -name "*.tf" | grep -q .; then
		if command -v terraform &>/dev/null; then
			log "Running terraform fmt --recursive..."
			terraform fmt --recursive
		else
			log "terraform not found. Skipping Terraform formatting."
		fi
	fi
}

# Fun
function laughing_at_idiots() {
	# sudo apt-get install -y fswebcam imagemagick
	(
		insults=(
			"MASSIVE FUCKING MORON"
			"YOU FOOL"
			"HAHA HACKED YA"
		)
		random_index=$((RANDOM % ${#insults[@]}))
		random_insult="${insults[$random_index]}"

		filepath="/tmp/mug.jpeg"
		fswebcam -r 1080x1920 --skip 100 "$filepath" >/dev/null 2>&1
		convert "$filepath" -gravity North -pointsize 72 -fill red -annotate 0 "$random_insult" "$filepath" >/dev/null 2>&1
		eog -f "$filepath" >/dev/null 2>&1
	) >/dev/null 2>&1 &
	disown
}
