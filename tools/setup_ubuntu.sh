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
    sudo apt-get install \
            python3-pip

    # Apt install
    sudo apt install \
            curl \
            wget \
            figlet \
            terminator \
            docker.io \
            dos2unix

    sudo systemctl enable --now docker && sudo docker run hello-world


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
    
    snap install --edge terraform
    # Install Chrome
    wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
    sudo apt install ./google-chrome-stable_current_amd64.deb
    
    # Install Jetbrains Toolbox
    curl -fsSL https://raw.githubusercontent.com/nagygergo/jetbrains-toolbox-install/master/jetbrains-toolbox.sh | bash
}

set_up_pyenv() {
    sudo apt-get update
    sudo apt-get install \
        make \
        build-essential \
        libssl-dev \
        zlib1g-dev \
        libbz2-dev \
        libreadline-dev \
        libsqlite3-dev \
        wget \
        curl 
        llvm \
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
