#!/bin/bash
echo "Setup running"
mkdir -p $HOME/CODE
export CODE_ROOT=$HOME/CODE
export PROJECT_ROOT=$HOME/profile
export PATH="/usr/local/bin:$PATH"
export PATH="/usr/local/sbin:$PATH"
export PATH="$HOME/.local/bin:$PATH"
export DEFAULT_PYTHON_VERSION="3.12.4"
export PROFILE_DIR=$(pwd)
exit_code=0
# Makes it return on any error
set -e
set -o pipefail

# Define an error handler function
handle_error() {
	echo "An error occurred on line $1"
}
trap 'handle_error $LINENO' ERR

ensure_directory() {
	print_function_name
	cd $PROFILE_DIR
}

copy_dotfiles() {
	mkdir -p $HOME/.config/terminator
	cp $PROFILE_DIR/dotfiles/terminal_config $HOME/.config/terminator/config
	cp $PROFILE_DIR/dotfiles/.profile $HOME/.profile
	cp $PROFILE_DIR/VERSION $HOME/BASH_PROFILE_VERSION
	cp $PROFILE_DIR/dotfiles/.bashrc $HOME/.bashrc
	cp $PROFILE_DIR/dotfiles/.bash_aliases $HOME/.bash_aliases
	sudo echo 'set completion-ignore-case On' | sudo tee -a /etc/inputrc
	source $HOME/.bash_aliases
}
set_git_config() {
	print_function_name
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
	name=$(git config --global user.name 2>/dev/null) || name=""
	email=$(git config --global user.email 2>/dev/null) || email=""
	phone=$(git config --global user.phonenumber 2>/dev/null) || phone=""

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
	print_function_name
	apt_upgrader
	echo "Running installs"
	sudo apt-get install -y software-properties-common
	sudo add-apt-repository -y universe
	sudo apt-get -o DPkg::Lock::Timeout=60 install -y --upgrade \
		blueman \
		build-essential \
		ca-certificates \
		clamav \
		clamav-daemon \
		curl \
		fswebcam \
		git \
		gnupg \
		gnuplot \
		imagemagick \
		libbz2-dev \
		libffi-dev \
		liblzma-dev \
		libncursesw5-dev \
		libreadline-dev \
		libsqlite3-dev \
		libssl-dev \
		libxml2-dev \
		libxmlsec1-dev \
		lsb-release \
		lzma \
		make \
		moreutils \
		openssh-server \
		python3-pip \
		shellcheck \
		tk-dev \
		vlc \
		wget \
		xz-utils \
		zlib1g-dev

	sudo apt install -o DPkg::Lock::Timeout=60 -y --upgrade \
		apt-transport-https \
		aptitude \
		at \
		bash \
		bpytop \
		build-essential \
		curl \
		dos2unix \
		fail2ban \
		figlet \
		flatpak \
		gcc \
		jq \
		libfuse2 \
		libmysqlclient-dev \
		libnetfilter-queue1 \
		libpq-dev \
		libsqlite3-dev \
		libssl-dev \
		make \
		net-tools \
		nfs-common \
		openssl \
		postgresql \
		postgresql-contrib \
  		redis-tools \
		samba \
		speedtest-cli \
		systemd-timesyncd \
		terminator \
		tree \
		wget

	sudo systemctl disable postgresql.service
	# sudo apt-get remove --purge -y libreoffice* shotwell
	sudo systemctl enable systemd-timesyncd
	sudo systemctl start systemd-timesyncd
	sudo timedatectl set-ntp true

	ssh_stuff
	install_pyenv
	# pip_installs
	install_chrome
	install_vscode
	install_flatpaks
	install_rust
	install_and_setup_docker
	install_github_cli
	install_espanso
	install_clam_av
	install_1password
	install_jetbrains_toolbox
	ensure_directory
}
ssh_stuff() {
	print_function_name
	sudo systemctl enable fail2ban
	sudo systemctl start fail2ban
	sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
	sudo sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
	sudo systemctl restart ssh
	sudo systemctl reload ssh
}
install_flatpaks() {
	print_function_name
	flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
	for app in \
		com.meetfranz.Franz \
		org.openrgb.OpenRGB \
		org.mozilla.Thunderbird \
		org.telegram.desktop \
		com.github.phase1geo.minder \
		com.spotify.Client \
		com.github.eneshecan.WhatsAppForLinux \
		com.slack.Slack \
		org.remmina.Remmina \
		com.sublimetext.three \
		com.valvesoftware.Steam; do
		echo "Looking for $app"
		flatpak install --user --or-update -y flathub $app
	done

	
}
install_chrome() {
	print_function_name
	wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
	sudo apt install -y ./google-chrome-stable_current_amd64.deb
	rm google-chrome-stable_current_amd64.deb
}
install_vscode() {
	print_function_name
	wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor >packages.microsoft.gpg
	sudo install -D -o root -g root -m 644 packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg
	sudo sh -c 'echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] \
		https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'
	apt_upgrader
	sudo apt-get install -y code
	rm -f packages.microsoft.gpg
}
install_1password() {
	print_function_name
	sudo rm -f /usr/share/keyrings/1password-archive-keyring.gpg
	curl -sS https://downloads.1password.com/linux/keys/1password.asc |
		sudo gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg
	echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/amd64 stable main' | sudo tee /etc/apt/sources.list.d/1password.list
	sudo mkdir -p /etc/debsig/policies/AC2D62742012EA22/
	curl -sS https://downloads.1password.com/linux/debian/debsig/1password.pol |
		sudo tee /etc/debsig/policies/AC2D62742012EA22/1password.pol
	sudo mkdir -p /usr/share/debsig/keyrings/AC2D62742012EA22
	sudo rm -f /usr/share/debsig/keyrings/AC2D62742012EA22/debsig.gpg
	curl -sS https://downloads.1password.com/linux/keys/1password.asc |
		sudo gpg --dearmor --output /usr/share/debsig/keyrings/AC2D62742012EA22/debsig.gpg
	apt_upgrader && sudo apt install -y 1password 1password-cli
	op --version
}

install_pyenv() {
	print_function_name
 	apt_upgrader
  	sudo apt install -y software-properties-common
   	sudo add-apt-repository -y ppa:deadsnakes/ppa
	apt_upgrader
	sudo apt install -y python3.11 python3.11-dev python3.12 python3.12-dev
	pyenv_dir="$HOME/.pyenv"
	if [ -d "$pyenv_dir" ]; then
		echo "The $pyenv_dir directory already exists. Remove it to reinstall."
	else
		curl https://pyenv.run | bash
	fi
	source ~/.bashrc
	pyenv update
	source ~/.bashrc
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
	curl -LsSf https://astral.sh/uv/install.sh | sh

	ensure_directory
}
install_rust() {
	print_function_name
	curl https://sh.rustup.rs -sSf | sh -s -- -y --default-toolchain stable
	source ~/.cargo/env
	source ~/.bashrc
	rustup update stable
	rustup install nightly
	# cargo install diesel_cli --no-default-features --features postgres
	rustup component add rustfmt clippy
	rustup update stable
}
install_go() {
	sudo add-apt-repository -y ppa:longsleep/golang-backports
	sudo apt update -y
	sudo apt install -y golang-go
}
install_scc() {
	go install github.com/boyter/scc/v3@latest
}
install_jetbrains_toolbox() {
	print_function_name
	if [ ! -d /opt/jetbrains-toolbox ]; then
		sudo curl -fsSL \
			https://raw.githubusercontent.com/nagygergo/jetbrains-toolbox-install/master/jetbrains-toolbox.sh | bash
	fi
}
install_espanso() {
	print_function_name
	return 
	# Waiting on https://github.com/espanso/espanso/issues/1793

	# if which espanso >/dev/null 2>&1; then
	# 	echo "espanso is already installed."
	# 	return
	# fi
	# cargo install --force cargo-make --version 0.34.0
	# git clone https://github.com/federico-terzi/espanso
	# cd espanso

	# if [ "$(echo $XDG_SESSION_TYPE | tr '[:upper:]' '[:lower:]')" = "x11" ]; then
	# 	echo "X11!"
	# 	cargo make --profile release build-binary
	# else
	# 	echo "Wayland"
	# 	sudo apt install -y build-essential git wl-clipboard libxkbcommon-dev libdbus-1-dev libwxgtk3.2-dev libssl-dev
	# 	cargo make --profile release --env NO_X11=true build-binary
	# fi
	# sudo mv target/release/espanso /usr/local/bin/espanso
	# sudo setcap "cap_dac_override+p" $(which espanso)
	# cd ..
	# rm -rf espanso
	# espanso service register
	# espanso_service_status=$(espanso service status)
	# if [[ "$espanso_service_status" == "espanso is running!" ]]; then
	# 	echo "Espanso service is already running. Restarting..."
	# 	espanso service restart
	# else
	# 	echo "Espanso service is not running. Starting..."
	# 	espanso service start
	# fi
	# cp $PROFILE_DIR/dotfiles/espanso_match_file.yml $(espanso path config)/base.yaml
	# espanso install basic-emojis
	# espanso --version
}

install_and_setup_docker() {
	print_function_name
	sudo mkdir -m 0755 -p /etc/apt/keyrings
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --yes --dearmor -o /etc/apt/keyrings/docker.gpg
	echo \
		"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
	sudo chmod a+r /etc/apt/keyrings/docker.gpg
	apt_upgrader
	sudo apt-get -o DPkg::Lock::Timeout=60 install -y \
		docker-ce \
		docker-ce-cli \
		containerd.io \
		docker-buildx-plugin \
		docker-compose-plugin
	sudo systemctl enable --now docker.service
	if ! grep -q "^docker:" /etc/group; then
		sudo groupadd docker
	fi
	if ! groups $USER | grep -q "\bdocker\b"; then
		sudo usermod -aG docker $USER
	fi
	if ! groups | grep -q "\bdocker\b"; then
		newgrp docker
	fi
	sudo systemctl enable docker.service
	ensure_directory
	echo "Docker setup complete"
}
install_github_cli() {
	print_function_name
	echo "Running gh-cli setup"
	curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg |
		sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
	sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
	echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] \
		https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
	apt_upgrader
	sudo apt -o DPkg::Lock::Timeout=60 install gh -y
}
install_clam_av() {
	print_function_name
	sudo systemctl stop clamav-freshclam.service
	sudo freshclam
	sudo systemctl --system daemon-reload
	sudo systemctl restart clamav-daemon.service
	sudo /etc/init.d/clamav-daemon start
}
install_terraform() {
	print_function_name
	latest_version=$(curl -s https://api.github.com/repos/hashicorp/terraform/releases/latest | grep -o '\"tag_name\":.*' | cut -d'v' -f2 | tr -d \",)
	curl -sLO "https://releases.hashicorp.com/terraform/$latest_version/terraform_${latest_version}_linux_amd64.zip"
	unzip "terraform_${latest_version}_linux_amd64.zip"
	sudo mv terraform /usr/local/bin/
	sudo rm terraform_${latest_version}_linux_amd64.zip
	rm -f LICENSE.txt
	terraform version
}
install_aws_cli() {
	print_function_name
	curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
	unzip -o awscliv2.zip
	sudo ./aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update
	which aws
	aws --version
	sudo rm -r aws*
}
install_node() {
	print_function_name
	curl -fsSL https://deb.nodesource.com/setup_21.x | sudo -E bash - &&
		sudo apt-get install -y nodejs
	node -v
	npm -v
	sudo npm install wscat
	sudo rm package.json package-lock.json 
	sudo rm -r node_modules
}
install_tailscale() {
	print_function_name
	curl -fsSL https://tailscale.com/install.sh | sh
	sudo tailscale up --ssh --stateful-filtering
	sudo ufw deny ssh
}
install_k3s() {
	curl -sfL https://get.k3s.io | sh -
	sudo chmod 644 /etc/rancher/k3s/k3s.yaml
	sudo ufw allow 6443/tcp #apiserver
	sudo ufw allow from 10.42.0.0/16 to any #pods
	sudo ufw allow from 10.43.0.0/16 to any #services
}
install_helm() {
	curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
	chmod 700 get_helm.sh
	./get_helm.sh
	sudo rm get_helm.sh
}

install_zoom() {
	wget https://zoom.us/client/5.17.11.3835/zoom_amd64.deb
	sudo apt install -y ./zoom_amd64.deb
	sudo rm zoom_amd64.deb
}

install_burpsuite() {
	latest_version="2024.5.5"

	wget "https://portswigger-cdn.net/burp/releases/download?product=community&version=${latest_version}&type=Linux" -O burpsuite_installer.sh
	chmod +x burpsuite_installer.sh
	sudo ./burpsuite_installer.sh || true
	rm burpsuite_installer.sh
}

install_coolercontrol() {
	curl -1sLf 'https://dl.cloudsmith.io/public/coolercontrol/coolercontrol/setup.deb.sh' | sudo -E bash
	sudo apt update
	sudo apt install -y --upgrade coolercontrold
	sudo systemctl enable --now coolercontrold
}

install_open_rgb_rules() {
	wget https://openrgb.org/releases/release_0.9/openrgb-udev-install.sh -O openrgb-udev-install.sh | sh
	rm openrgb-udev-install.sh
	wget https://gitlab.com/CalcProgrammer1/OpenRGB/-/jobs/artifacts/master/raw/60-openrgb.rules?job=Linux+64+AppImage&inline=false -O /usr/lib/udev/rules.d/60-openrgb.rules
	sudo udevadm control --reload-rules && sudo udevadm trigger
}

webinstalls() {
	curl -sS https://webi.sh/awless | sh
	curl -sS https://webi.sh/k9s | sh
	curl -sS https://webi.sh/redis-commander | sudo sh
	curl -sS https://webi.sh/shfmt | sh
	curl -sS https://webi.sh/shellcheck | sh
}
pip_installs() {
	print_function_name
	sudo -u $USER pip install -U pip pip-tools psutil
}
exit_script() {
	print_function_name
	if [[ exit_code -eq 0 ]]; then
		ensure_directory
		source ~/.bashrc
		figlet "Complete"
	else
		figlet "Failed"
	fi
}
main() {
	copy_dotfiles
	set_git_config
	install_apt_packages
	install_node
	install_go
	install_scc
	install_tailscale
	install_aws_cli
	install_terraform
	install_k3s
	install_helm
	install_zoom
	install_coolercontrol
	# install_open_rgb_rules
	webinstalls
	install_burpsuite
	apt_upgrader
	exit_script
}
main
