#!/bin/bash
echo "Setup running"
mkdir -p $HOME/CODE
export CODE_ROOT=$HOME/CODE
export PROJECT_ROOT=$HOME/profile
export PATH="/usr/local/bin:$PATH"
export PATH="/usr/local/sbin:$PATH"
export PATH="$HOME/.local/bin:$PATH"
export DEFAULT_PYTHON_VERSION="3.12"
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
	log "Running installs"
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
		libwxgtk3.2-dev \
		lsb-release \
		lzma \
		make \
		m4 \
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
		bat \
		bpytop \
		build-essential \
		curl \
		dos2unix \
		fail2ban \
		figlet \
		flatpak \
		gcc \
		jq \
		libbz2-dev \
		libffi-dev \
		libfuse2 \
		liblzma-dev \
		libmysqlclient-dev \
		libncursesw5-dev \
		libnetfilter-queue1 \
		libpq-dev \
		libreadline-dev \
		libsqlite3-dev \
		libssl-dev \
		libxml2-dev \
		libxmlsec1-dev \
		llvm \
		lsd \
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
		steam-devices \
		terminator \
		tk-dev \
		tree \
		wget \
		xz-utils \
		zlib1g-dev


	sudo systemctl disable postgresql.service
	# sudo apt-get remove --purge -y libreoffice* shotwell
	sudo systemctl enable systemd-timesyncd
	sudo systemctl start systemd-timesyncd
	sudo timedatectl set-ntp true

	ssh_stuff
	install_pyenv
	# pip_installs
	install_browser
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

install_slack() {
	architecture=$(dpkg --print-architecture)
    if [ "$architecture" != "arm64" ]; then
		wget https://downloads.slack-edge.com/desktop-releases/linux/x64/4.41.96/slack-desktop-4.41.96-amd64.deb
		sudo apt install ./slack-desktop-*.deb
		sudo rm -f slack-desktop-*
	fi
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
        org.telegram.desktop \
        org.openrgb.OpenRGB \
        org.mozilla.Thunderbird \
        com.spotify.Client \
        com.github.eneshecan.WhatsAppForLinux \
        org.remmina.Remmina \
        com.sublimetext.three \
        com.valvesoftware.Steam; do
        log "Looking for $app"
        if flatpak install --user --or-update -y flathub $app; then
            log "Successfully installed $app"
        else
            log "Failed to install $app - continuing with next application"
        fi
    done    
}

install_browser() {
	print_function_name
	if command -v vivaldi >/dev/null 2>&1; then
        log "Vivaldi is already installed, skipping installation"
        return 0
    fi
    architecture=$(dpkg --print-architecture)

    if [ "$architecture" = "arm64" ]; then
        log "Downloading Vivaldi for ARM64"
        wget https://downloads.vivaldi.com/stable/vivaldi-stable_7.1.3570.42-1_arm64.deb
    else
        log "Downloading Vivaldi for x86_64"
        wget https://downloads.vivaldi.com/stable/vivaldi-stable_7.1.3570.42-1_amd64.deb
    fi
    sudo apt install -y ./vivaldi-stable*.deb
    rm -f vivaldi-stable*.deb
    log "Vivaldi installation completed"
}

install_vscode() {
	print_function_name
	if command -v code >/dev/null 2>&1; then
        log "VSCode is already installed, skipping installation"
        return 0
    fi
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
    architecture=$(dpkg --print-architecture)
    
    # Clean up any previous installation
    sudo rm -rf /opt/1Password 1password-latest.tar.gz 1password-*

    # Download appropriate version based on architecture
    if [ "$architecture" = "arm64" ]; then
        log "Downloading 1Password for ARM64"
        curl -sSO https://downloads.1password.com/linux/tar/stable/aarch64/1password-latest.tar.gz
        curl -sSO https://downloads.1password.com/linux/tar/stable/aarch64/1password-latest.tar.gz.sig
    else
        log "Downloading 1Password for x86_64"
        curl -sSO https://downloads.1password.com/linux/tar/stable/x86_64/1password-latest.tar.gz
        curl -sSO https://downloads.1password.com/linux/tar/stable/x86_64/1password-latest.tar.gz.sig
    fi

    # Verify GPG signature (optional but recommended)
    curl -sS https://downloads.1password.com/linux/keys/1password.asc | gpg --import
    gpg --verify 1password-latest.tar.gz.sig 1password-latest.tar.gz || {
        log "GPG verification failed"
        return 1
    }

    # Extract and install
    sudo tar -xf 1password-latest.tar.gz
    sudo mkdir -p /opt/1Password
    sudo mv 1password-*/* /opt/1Password/
    sudo /opt/1Password/after-install.sh

    # Clean up downloaded files
    rm -f 1password-latest.tar.gz 1password-latest.tar.gz.sig
    rm -rf 1password-*/

    # Verify installation
    if command -v 1password >/dev/null 2>&1; then
        log "1Password installed successfully"
        1password --version
    else
        log "1Password installation failed"
        return 1
    fi
}

install_pyenv() {
	print_function_name
	apt_upgrader
	sudo apt install -y software-properties-common python3.12 python3.12-dev
	pyenv_dir="$HOME/.pyenv"
	if [ -d "$pyenv_dir" ]; then
		log "The $pyenv_dir directory already exists. Remove it to reinstall."
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

go_installs() {
	print_function_name
	go install github.com/dim13/otpauth@latest
}

install_go() {
	print_function_name
	sudo add-apt-repository -y ppa:longsleep/golang-backports
	sudo apt update -y
	sudo apt install -y golang-go
	go_installs
}
install_scc() {
	print_function_name
	go install github.com/boyter/scc/v3@latest
}
install_jetbrains_toolbox() {
	print_function_name
	if command -v jetbrains-toolbox >/dev/null 2>&1; then
        log "Jetbrains toolbox is already installed, skipping installation"
        return 0
    fi
	bash jetbrains_toolbox_installer.sh
}
install_espanso() {
	print_function_name
	if command -v espanso >/dev/null 2>&1; then
        log "espanso is already installed, skipping installation"
        return 0
    fi
	# Waiting on https://github.com/espanso/espanso/issues/1793
	if [ "$(echo $XDG_SESSION_TYPE | tr '[:upper:]' '[:lower:]')" = "x11" ]; then
		echo "X11!"
	else
		log "Wayland"
		# sudo apt-get install libwxgtk3.2-dev
		# sudo apt install -y build-essential git wl-clipboard libxkbcommon-dev libdbus-1-dev libwxgtk3.2-dev libssl-dev
		# wget https://github.com/espanso/espanso/releases/download/v2.2.1/espanso-debian-wayland-amd64.deb
		# sudo apt install ./espanso-debian-wayland-amd64.deb
		sudo apt update
		sudo apt install build-essential git wl-clipboard libxkbcommon-dev libdbus-1-dev libssl-dev libwxgtk3.*-dev
		cargo install --force cargo-make --version 0.37.23
		git clone https://github.com/espanso/espanso
		cd espanso
		cargo make --profile release --env NO_X11=true build-binary 
		sudo mv target/release/espanso /usr/local/bin/espanso
		cd ..
		sudo rm -r espanso
	fi
	sudo setcap "cap_dac_override+p" $(which espanso)
	espanso service register
	espanso service status | tee >(grep -q "is running" && \
		(espanso service stop && espanso service start) || \
		(espanso service start))

	cp $PROFILE_DIR/dotfiles/espanso_match_file.yml $(espanso path config)/match/base.yml
	espanso --version
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
        # Use sg instead of newgrp - it runs the command in a new group context without starting a new shell
        sg docker -c "echo 'Docker group permissions applied for this session'"
    fi
    sudo systemctl enable docker.service
    ensure_directory
    log "Docker setup complete"
}

install_github_cli() {
	print_function_name
	log "Running gh-cli setup"
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
	print_function_name
	curl -sfL https://get.k3s.io | sh -
	sudo chmod 644 /etc/rancher/k3s/k3s.yaml
	sudo ufw allow 6443/tcp #apiserver
	sudo ufw allow from 10.42.0.0/16 to any #pods
	sudo ufw allow from 10.43.0.0/16 to any #services

	# Containerd perms
    if ! id -nG "$USER" | grep -qw "containerd"; then
		sudo groupadd containerd
        sudo usermod -aG containerd "$USER"
        newgrp containerd
		sudo chgrp containerd /run/k3s/containerd/containerd.sock
    	sudo chmod 660 /run/k3s/containerd/containerd.sock
    fi
}
install_helm() {
	print_function_name
	curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
	chmod 700 get_helm.sh
	./get_helm.sh
	sudo rm get_helm.sh
}

install_zoom() {
	print_function_name
	wget https://zoom.us/client/5.17.11.3835/zoom_amd64.deb
	sudo apt install -y ./zoom_amd64.deb
	sudo rm zoom_amd64.deb
}

install_burpsuite() {
	print_function_name
	latest_version="2024.5.5"

	wget "https://portswigger-cdn.net/burp/releases/download?product=community&version=${latest_version}&type=Linux" -O burpsuite_installer.sh
	chmod +x burpsuite_installer.sh
	sudo ./burpsuite_installer.sh || true
	rm burpsuite_installer.sh
}

install_coolercontrol() {
	print_function_name
	curl -1sLf 'https://dl.cloudsmith.io/public/coolercontrol/coolercontrol/setup.deb.sh' | sudo -E bash
	sudo apt update
	sudo apt install -y --upgrade coolercontrold
	sudo systemctl enable --now coolercontrold
}

install_open_rgb_rules() {
	print_function_name
	wget https://openrgb.org/releases/release_0.9/openrgb-udev-install.sh -O openrgb-udev-install.sh | sh
	rm openrgb-udev-install.sh
	wget https://gitlab.com/CalcProgrammer1/OpenRGB/-/jobs/artifacts/master/raw/60-openrgb.rules?job=Linux+64+AppImage&inline=false -O /usr/lib/udev/rules.d/60-openrgb.rules
	sudo udevadm control --reload-rules && sudo udevadm trigger
}

install_font() {
	print_function_name
	wget https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/FiraCode.zip -O FiraCode.zip
	unzip -o FiraCode.zip -d ~/.local/share/fonts
	fc-cache -fv
	rm -f FiraCode.zip
}
webinstalls() {
	print_function_name
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
    # Array to store failed functions
    failed_functions=()

    # Helper function to run and track failures
    run_function() {
        local func_name=$1
        if ! $func_name; then
            failed_functions+=("$func_name")
            echo "Warning: $func_name failed, continuing with next function..."
        fi
    }

    # Run all functions
    run_function copy_dotfiles
    run_function set_git_config
    run_function install_apt_packages
	run_function install_slack
    run_function install_node
    run_function install_go
    run_function install_scc
    run_function install_tailscale
    run_function install_aws_cli
    # run_function install_terraform
    # run_function install_k3s
    run_function install_helm
    # run_function install_zoom
    # run_function install_coolercontrol
    run_function install_open_rgb_rules
    run_function webinstalls
    run_function install_font
    # run_function install_burpsuite
    run_function apt_upgrader

    # Report failures if any
	if [ ${#failed_functions[@]} -ne 0 ]; then
		echo -e "\n\033[1;91mThe following functions failed:\033[0m"
		printf '\033[1;91m%s\033[0m\n' "${failed_functions[@]}"
		echo -e "\n\033[1;91mPlease check the above functions and try running them individually.\033[0m"
	fi

    exit_script
}
main
