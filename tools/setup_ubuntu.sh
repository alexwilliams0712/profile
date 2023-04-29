#!/bin/bash

echo "Setup running"

mkdir -p $HOME/CODE
export CODE_ROOT=$HOME/CODE
export PROJECT_ROOT=$HOME/profile
export PATH="/usr/local/bin:$PATH"
export PATH="/usr/local/sbin:$PATH"
export PATH="$HOME/.local/bin:$PATH"
export DEFAULT_PYTHON_VERSION="3.11.2"
export PROFILE_DIR=$(pwd)

copy_dotfiles() {
	mkdir -p $HOME/.config/terminator
	cp $PROFILE_DIR/dotfiles/terminal_config $HOME/.config/terminator/config
	cp $PROFILE_DIR/dotfiles/.profile $HOME/.profile
	cp $PROFILE_DIR/dotfiles/.bashrc $HOME/.bashrc
	cp $PROFILE_DIR/dotfiles/.bash_aliases $HOME/.bash_aliases
	# you may have to use this instead if you are not a superuser:
	sudo echo 'set completion-ignore-case On' | sudo tee -a /etc/inputrc
	# Git config setup
	git config --global core.autocrlf false
	git config --global pull.rebase false
	git config --global http.sslVerify false
	git config --global diff.tool bc3
	git config --global color.branch auto
	git config --global color.diff auto
	git config --global color.interactive auto
	git config --global color.status auto
	git config --global push.default simple
	git config --global merge.tool kdiff3
	git config --global difftool.prompt false
	git config --global alias.c commit
	git config --global alias.ca 'commit -a'
	git config --global alias.cm 'commit -m'
	git config --global alias.cam 'commit -am'
	git config --global alias.d diff
	git config --global alias.dc 'diff --cached'
	git config --global alias.l 'log --graph --pretty=format:"%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset" --abbrev-commit'
	name=$(git config --global user.name)
	email=$(git config --global user.email)
	phone=$(git config --global user.phonenumber)
	if [ -z "$name" ]; then
		read -p "Enter github username: " name && git config --global user.name "$name"
	fi
	read -p "Enter github email address (leave blank to keep current): " new_email
	if [ ! -z "$new_email" ]; then
		git config --global user.email "$new_email"
	else
		new_email="$email"
	fi

	read -p "Enter phone number (leave blank to keep current): " new_phone
	if [ ! -z "$new_phone" ]; then
		git config --global user.phonenumber "$new_phone"
	else
		new_phone="$phone"
	fi
}

install_apt_packages() {
	sudo apt update

	# Apt gets
	sudo apt-get install -y \
		ca-certificates \
		curl \
		gnupg \
		lsb-release \
		python3-pip \
		shellcheck

	# Apt install
	sudo apt install -y \
		curl \
		wget \
		figlet \
		terminator \
		glances \
		htop \
		bpytop \
		piper \
		libfuse2 \
		dos2unix \
		net-tools \
		libsqlite3-dev \
		libpq-dev \
		samba \
		libmysqlclient-dev \
		speedtest-cli

	# Install Tweaks
	sudo add-apt-repository -y universe
	sudo apt install -y $(apt search gnome-shell-extension | grep ^gnome | cut -d / -f1)
	sudo apt -y autoremove

	# Global pip installs
	pip install -U pip pip-tools black isort

	# Apt removes
	sudo apt-get remove --purge -y ibus
	sudo apt autoremove -y
	sudo apt full-upgrade -y

	# Distro upgrader
	sudo apt update -y
	sudo apt upgrade -y
	sudo apt dist-upgrade
	sudo apt install update-manager-core
}

install_snaps() {
	# Snap classic install
	for i in \
		code \
		sublime-text \
		espanso \
		go; do
		sudo snap install $i --classic
	done

	# Snap  install
	for i in \
		k9s-nsg \
		1password; do
		sudo snap install $i
	done

	# Snap removes
	for i in \
		firefox \
		rpi-imager; do
		sudo snap remove $i --no-wait --purge
	done

	# Update all installed snaps
	sudo snap refresh
}

setup_espanso() {
	## Espanso settings, installation is done in install_snaps
	# Register espanso as a systemd service (required only once)
	espanso service register
	# Start espanso
	espanso start
	espanso --version
	# Set email and phone matches
	email=$(git config --global user.email)
	phone=$(git config --global user.phonenumber)
	config_file="$HOME/.config/espanso/match/base.yml"

	# Copy the espanso_match_file.yml to the Espanso configuration directory
	cp "$PROFILE_DIR/dotfiles/espanso_match_file.yml" "$config_file"

	# Replace email and phone placeholders with the values from Git config
	sed -i "s|youremail@example.com|$email|g; s|07123456789|$phone|g" "$config_file"
	espanso restart
}

install_rust() {
	sudo apt update && sudo apt upgrade -y
	sudo apt install -y curl gcc make build-essential
	curl https://sh.rustup.rs -sSf | sh -s -- -y --default-toolchain stable
	source "$HOME"/.bashrc
	rustup update stable
	# Install diesel cli for databases
	cargo install diesel_cli --no-default-features --features postgres
}

install_jetbrains_toolbox() {
	# Install Jetbrains Toolbox
	if [ ! -d /opt/jetbrains-toolbox ]; then
		curl -fsSL https://raw.githubusercontent.com/nagygergo/jetbrains-toolbox-install/master/jetbrains-toolbox.sh | bash
	fi
	cd /opt/jetbrains-toolbox
	jetbrains-toolbox

	# Copy watcherDefaultTasks.xml to every PyCharm options directory
	if [ -d ~/.config/JetBrains ]; then
		for pycharm_dir in ~/.config/JetBrains/PyCharm*; do
			if [ -d "$pycharm_dir" ]; then
				mkdir -p "${pycharm_dir}/options"
				echo "Copying to ${pycharm_dir}/options/watcherDefaultTasks.xml"
				cp $PROFILE_DIR/dotfiles/watcherDefaultTasks.xml ${pycharm_dir}/options/watcherDefaultTasks.xml
			fi
		done
	fi
}

install_chrome() {
	# Install Chrome
	wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
	sudo apt install ./google-chrome-stable_current_amd64.deb
	rm google-chrome-stable_current_amd64.deb
}

install_and_setup_docker() {
	# Install Docker
	sudo mkdir -m 0755 -p /etc/apt/keyrings
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg -y
	echo \
		"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
	sudo chmod a+r /etc/apt/keyrings/docker.gpg
	sudo apt-get update -y
	sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
	sudo systemctl enable --now docker
	# Check if the docker group exists
	if ! grep -q "^docker:" /etc/group; then
		sudo groupadd docker
	fi

	# Add the current user to the docker group
	if ! groups $USER | grep -q "\bdocker\b"; then
		sudo usermod -aG docker $USER
	fi

	# Activate the new group membership
	if ! groups | grep -q "\bdocker\b"; then
		newgrp docker
	fi

	# Enable the Docker service
	sudo systemctl enable docker.service
}

install_github_cli() {
	echo "running gh setup"
	type -p curl >/dev/null || sudo apt install curl -y
	curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg &&
		sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg &&
		echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null &&
		sudo apt update &&
		sudo apt install gh -y
}

install_terraform() {
	# Get the latest version of Terraform from the GitHub repository
	latest_version=$(curl -s https://api.github.com/repos/hashicorp/terraform/releases/latest | grep -o '\"tag_name\":.*' | cut -d'v' -f2 | tr -d \",)

	# Download and extract the latest version of Terraform
	curl -sLO "https://releases.hashicorp.com/terraform/${latest_version}/terraform_${latest_version}_linux_amd64.zip"
	unzip "terraform_${latest_version}_linux_amd64.zip"
	sudo mv terraform /usr/local/bin/
	sudo rm terraform_${latest_version}_linux_amd64.zip
	# Verify installation
	terraform version
}

install_spotify() {
	curl -sS https://download.spotify.com/debian/pubkey_7A3A762FAFD4A51F.gpg | sudo gpg --dearmor --yes -o /etc/apt/trusted.gpg.d/spotify.gpg
	echo "deb http://repository.spotify.com stable non-free" | sudo tee /etc/apt/sources.list.d/spotify.list
	sudo apt-get update && sudo apt-get install spotify-client
}

install_aws_cli() {
	curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
	unzip -o awscliv2.zip
	sudo ./aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update
	which aws
	aws --version
}

install_surfshark() {
	sudo curl -f https://downloads.surfshark.com/linux/debian-install.sh --output surfshark-install.sh
	sudo sh surfshark-install.sh
	sudo rm -f surfshark-install.sh
}

install_franz() {
	export FRANZ_VERSION=$(curl https://api.github.com/repos/meetfranz/franz/releases/latest -s | jq .name -r)
	sudo curl -fsSL https://github.com/meetfranz/franz/releases/download/v5.9.2/franz_5.9.2_amd64.deb -o franz_$FRANZ_VERSION\_amd64.deb
	sudo dpkg -i franz_$FRANZ_VERSION\_amd64.deb
	sudo rm -f franz_$FRANZ_VERSION\_amd64.deb
}

install_node() {
	curl -fsSL https://deb.nodesource.com/setup_19.x | sudo -E bash - &&
		sudo apt-get install -y nodejs
	sudo npm install -g npm
	node -v
	npm -v
	npm config set prefix '~/.npm-global'
}

set_up_pyenv() {
	echo "Setting up pyenv"
	sudo apt-get update -y
	sudo apt-get install -y \
		make \
		build-essential \
		libssl-dev \
		zlib1g-dev \
		libbz2-dev \
		libreadline-dev \
		libsqlite3-dev \
		wget \
		curl \
		libncursesw5-dev \
		xz-utils \
		tk-dev \
		libxml2-dev \
		libxmlsec1-dev \
		libffi-dev \
		lzma \
		libbz2-dev \
		liblzma-dev
	curl https://pyenv.run | bash
	pyenv update
	pyenv install -s $DEFAULT_PYTHON_VERSION
	pyenv global $DEFAULT_PYTHON_VERSION

	FOLDER=$(pyenv root)/plugins/pyenv-virtualenv
	URL=https://github.com/pyenv/pyenv-virtualenv.git
	if [ ! -d "$FOLDER" ]; then
		git clone $URL $FOLDER
	else
		cd "$FOLDER"
		git pull $URL
	fi
}

exit_script() {
	if [[ exit_code -eq 0 ]]; then
		cd $PROFILE_DIR
		source ~/.bashrc
		figlet "* Complete *"
	else
		figlet "Failed to install"
	fi
	echo "Press Enter to Exit..."
	read
}

main() {
	copy_dotfiles
	install_apt_packages
	install_snaps
	set_up_pyenv
	install_rust
	install_node
	install_github_cli
	install_aws_cli
	install_and_setup_docker
	install_chrome
	install_terraform
	install_surfshark
	install_franz
	install_spotify
	install_jetbrains_toolbox
	setup_espanso
	exit_script
}

main
