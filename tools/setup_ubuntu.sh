#!/bin/bash

echo "Setup running"

mkdir -p $HOME/CODE
export CODE_ROOT=$HOME/CODE
export PROJECT_ROOT=$HOME/profile
export PATH="/usr/local/bin:$PATH"
export PATH="/usr/local/sbin:$PATH"
export PATH="$HOME/.local/bin:$PATH"

copy_dotfiles() {
    cp $HOME/profile/dotfiles/.profile $HOME/.profile
    cp $HOME/profile/dotfiles/.bashrc $HOME/.bashrc
    cp $HOME/profile/dotfiles/.bash_aliases $HOME/.bash_aliases
    cp $HOME/profile/dotfiles/.gitconfig $HOME/.gitconfig


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
            dos2unix

    # Snap classic install
    for i in \
        code \
        sublime-text \
        terraform
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
    
    # Install Chrome
    wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
    sudo apt install ./google-chrome-stable_current_amd64.deb
    
    # Install Jetbrains Toolbox
    curl -fsSL https://raw.githubusercontent.com/nagygergo/jetbrains-toolbox-install/master/jetbrains-toolbox.sh | bash
    
    # Install Docker
    sudo mkdir -m 0755 -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    sudo apt-get update -y
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
#     sudo systemctl enable --now docker
#     sudo groupadd docker
#     sudo usermod -aG docker $USER
#     newgrp docker
#     sudo systemctl enable docker.service
    docker run hello-world
    
    
    # Install Tweaks
    sudo add-apt-repository universe
    sudo apt install $(apt search gnome-shell-extension | grep ^gnome | cut -d / -f1)
    
    sudo apt autoremove
}

set_up_pyenv() {
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
        curl 
        libncursesw5-dev \
        xz-utils \
        tk-dev \
        libxml2-dev \
        libxmlsec1-dev \
        libffi-dev \
        liblzma-dev
    curl https://pyenv.run | bash
    git clone https://github.com/pyenv/pyenv-virtualenv.git $(pyenv root)/plugins/pyenv-virtualenv
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
    # exit
}

main() {
    copy_dotfiles
    install_apt_packages
    set_up_pyenv
    exit_script
}

main
