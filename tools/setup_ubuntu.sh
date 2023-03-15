#!/bin/bash

echo "Setup running"

mkdir -p $HOME/CODE
export CODE_ROOT=$HOME/CODE
export PROJECT_ROOT=$HOME/profile
export PATH="/usr/local/bin:$PATH"
export PATH="/usr/local/sbin:$PATH"
export PATH="$HOME/.local/bin:$PATH"
export DEFAULT_PYTHON_VERSION="3.11.2"

copy_dotfiles() {
    cp $HOME/profile/dotfiles/.profile $HOME/.profile
    cp $HOME/profile/dotfiles/.bashrc $HOME/.bashrc
    cp $HOME/profile/dotfiles/.bash_aliases $HOME/.bash_aliases
    cp $HOME/profile/dotfiles/.gitconfig $HOME/.gitconfig
    read -p "Enter github username: " name && git config --global user.name "$name"
    read -p "Enter github email address: " email && git config --global user.email "$email"

    # you may have to use this instead if you are not a superuser:
    sudo echo 'set completion-ignore-case On' | sudo tee -a /etc/inputrc
}

install_apt_packages() {
    sudo apt update	
    
    # Apt gets
    sudo apt-get install -y \
            ca-certificates \
            curl \
            gnupg \
            lsb-release
            python3-pip
            
    # Apt install
    sudo apt install -y \
            curl \
            wget \
            figlet \
            terminator \
            piper \
            libfuse2 \
            dos2unix \
            net-tools \
            libsqlite3-dev \
            libpq-dev \
            samba \
            libmysqlclient-dev

    # Snap classic install
    for i in \
        code \
        sublime-text
    do
       sudo snap install $i --classic
    done

    # Snap  install
    for i in \
        k9s-nsg \
        1password 
    do
       sudo snap install $i
    done
    
    # Install Tweaks
    sudo add-apt-repository -y universe
    sudo apt install -y $(apt search gnome-shell-extension | grep ^gnome | cut -d / -f1)
    sudo apt -y autoremove
}

install_rust() {
  sudo apt update && sudo apt upgrade -y
  sudo apt install -y curl gcc make build-essential
  curl https://sh.rustup.rs -sSf | sh
  source "$HOME"/.bashrc
  # Install diesel cli for databases
  cargo install diesel_cli --no-default-features --features postgres
}

install_jetbrains_toolbox() {
    # Install Jetbrains Toolbox
    curl -fsSL https://raw.githubusercontent.com/nagygergo/jetbrains-toolbox-install/master/jetbrains-toolbox.sh | bash
    cd /opt/jetbrains-toolbox
    jetbrains-toolbox
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
      $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
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
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
        && sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
        && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
        && sudo apt update \
        && sudo apt install gh -y
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
    curl -f https://downloads.surfshark.com/linux/debian-install.sh --output surfshark-install.sh
    sudo sh surfshark-install.sh
}

install_franz() {
    export FRANZ_VERSION=$(curl https://api.github.com/repos/meetfranz/franz/releases/latest -s | jq .name -r)
    curl -fsSL https://github.com/meetfranz/franz/releases/download/v5.9.2/franz_5.9.2_amd64.deb -o franz_$FRANZ_VERSION\_amd64.deb
    sudo dpkg -i franz_$FRANZ_VERSION\_amd64.deb
    sudo rm -f franz_$FRANZ_VERSION\_amd64.deb
}

install_node() {
    curl -fsSL https://deb.nodesource.com/setup_19.x | sudo -E bash - &&\
    sudo apt-get install -y nodejs
    sudo npm install -g npm
    node -v
    npm -v
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
    if [ ! -d "$FOLDER" ] ; then
        git clone $URL $FOLDER
    else
        cd "$FOLDER"
        git pull $URL
    fi
}


exit_script() {
    if [[ exit_code -eq 0 ]]; then
        cd $HOME/profile
        source ~/.bashrc
        figlet "*** Fresh Install of Alex's Profile Complete! ***"
    else
        figlet "FATAL - Could not install Alex's Profile"
    fi
    echo "Press Enter to Exit..."
    read
}

main() {
    copy_dotfiles
    install_apt_packages
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
    exit_script
}

main
