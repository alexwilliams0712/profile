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
exit_code=0
copy_dotfiles() {
	mkdir -p $HOME/.config/terminator
	cp $PROFILE_DIR/dotfiles/terminal_config $HOME/.config/terminator/config
	cp $PROFILE_DIR/dotfiles/.profile $HOME/.profile
	cp $PROFILE_DIR/dotfiles/.bashrc $HOME/.bashrc
	cp $PROFILE_DIR/dotfiles/.bash_aliases $HOME/.bash_aliases
	sudo echo 'set completion-ignore-case On' | sudo tee -a /etc/inputrc
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
    	sudo add-apt-repository -y universe
	sudo apt-get install -y \
		ca-certificates \
		curl \
		git \
		gnupg \
		lsb-release \
		python3-pip \
		gnuplot \
		shellcheck

	sudo apt install -y \
		bpytop \
		curl \
		dos2unix \
		fail2ban \
		figlet \
		glances \
		htop \
		libfuse2 \
		libmysqlclient-dev \
		libpq-dev \
		libsqlite3-dev \
		net-tools \
		piper \
		postgresql \
		postgresql-contrib \
		samba \
		speedtest-cli \
		terminator \
		wget \
		$(apt search gnome-shell-extension | grep ^gnome | cut -d / -f1)

	
	sudo apt-get remove --purge -y libreoffice* shotwell
	sudo apt -y autoremove
	sudo apt-get remove --purge -y ibus
	sudo apt autoremove -y
	sudo apt full-upgrade -y
	sudo apt update -y
	sudo apt upgrade -y
	sudo apt dist-upgrade
	sudo apt install update-manager-core
    	pip install -U pip pip-tools black isort psutil
	sudo systemctl enable fail2ban
	sudo systemctl start fail2ban
	sudo systemctl start postgresql.service
}
ssh_stuff() {
	sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
	sudo sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
	sudo systemctl restart ssh
}
install_snaps() {
	for i in \
		code \
		sublime-text \
		go; do
		sudo snap install $i --classic
	done
	for i in \
		k9s-nsg \
		1password; do
		sudo snap install $i
	done
	for i in \
		firefox \
		rpi-imager; do
		sudo snap remove $i --no-wait --purge
	done
	sudo snap refresh
}
setup_espanso() {
	if [ "$XDG_SESSION_TYPE" = "X11" ]; then
		echo "X11!"
	else
		sudo sed -i 's/#WaylandEnable=false/WaylandEnable=false/g' /etc/gdm3/custom.conf
	fi
	sudo snap install espanso --classic --channel=latest/edge
	espanso service register
	espanso service start
	espanso --version
	email=$(git config --global user.email)
	phone=$(git config --global user.phonenumber)
	config_file="$HOME/.config/espanso/match/base.yml"
	cp "$PROFILE_DIR/dotfiles/espanso_match_file.yml" "$config_file"
	sed -i "s|youremail@example.com|$email|g; s|07123456789|$phone|g" "$config_file"
	espanso service restart
}
install_rust() {
	sudo apt update && sudo apt upgrade -y
	sudo apt install -y curl gcc make build-essential
	curl https://sh.rustup.rs -sSf | sh -s -- -y --default-toolchain stable
	source "$HOME"/.bashrc
	rustup update stable
	cargo install diesel_cli --no-default-features --features postgres
	rustup component add rustfmt clippy
	rustup update stable

}
install_jetbrains_toolbox() {
	if [ ! -d /opt/jetbrains-toolbox ]; then
		curl -fsSL https://raw.githubusercontent.com/nagygergo/jetbrains-toolbox-install/master/jetbrains-toolbox.sh | bash
	fi
	cd /opt/jetbrains-toolbox
	jetbrains-toolbox
	if [ -d ~/.config/JetBrains ]; then
	    for product_dir in ~/.config/JetBrains/*; do
		if [ -d "$product_dir" ]; then
		    mkdir -p "$product_dir/options"
		    echo "Copying to $product_dir/options/watcherDefaultTasks.xml"
		    cp $PROFILE_DIR/dotfiles/watcherDefaultTasks.xml $product_dir/options/watcherDefaultTasks.xml
		fi
	    done
	fi
}
install_chrome() {
	wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
	sudo apt install ./google-chrome-stable_current_amd64.deb
	rm google-chrome-stable_current_amd64.deb
}
install_and_setup_docker() {
	sudo mkdir -m 0755 -p /etc/apt/keyrings
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg -y
	echo \
		"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
	sudo chmod a+r /etc/apt/keyrings/docker.gpg
	sudo apt-get update -y
	sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
	sudo systemctl enable --now docker
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
}
install_github_cli() {
	echo "Running gh-cli setup"
	type -p curl >/dev/null || sudo apt install curl -y
	curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
	sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
	echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
	sudo apt update -y
	sudo apt install gh -y
}
install_terraform() {
	latest_version=$(curl -s https://api.github.com/repos/hashicorp/terraform/releases/latest | grep -o '\"tag_name\":.*' | cut -d'v' -f2 | tr -d \",)
	curl -sLO "https://releases.hashicorp.com/terraform/$latest_version/terraform_${latest_version}_linux_amd64.zip"
	unzip "terraform_${latest_version}_linux_amd64.zip"
	sudo mv terraform /usr/local/bin/
	sudo rm terraform_${latest_version}_linux_amd64.zip
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
	curl -fsSL https://deb.nodesource.com/setup_19.x | sudo -E bash - && sudo apt-get install -y nodejs
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
		figlet "Complete"
	else
		figlet "Failed"
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
	ssh_stuff
	exit_script
}
main
