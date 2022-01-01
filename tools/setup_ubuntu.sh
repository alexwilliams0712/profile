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
            figlet \
            terminator \
            docker.io \
            docker-compose \
            dos2unix

    sudo systemctl enable --now docker && sudo docker run hello-world


    # Snap classic install
    for i in \
        code \
        sublime-text \
        kubectl \
        helm

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
}



set_up_virtualenvwrapper() {
    #Virtualenvwrapper settings:
    export VIRTUALENVWRAPPER_PYTHON=/usr/bin/python3
    export WORKON_HOME=$HOME/.virtualenvs
    export VIRTUALENVWRAPPER_VIRTUALENV=/usr/local/bin/virtualenv
    export PATH="$VIRTUALENVWRAPPER_VIRTUALENV:$PATH"

    mkdir -p $WORKON_HOME
    sudo pip3 install virtualenv virtualenvwrapper

    source /usr/local/bin/virtualenvwrapper.sh
}

create_sandbox_venv() {
    cd $CODE_ROOT && mkdir -p sandbox && cd sandbox
    mkvirtualenv sandbox && setvirtualenvproject && deactivate
    cd $HOME/profile/tools
}

installkrew() {
  set -x; cd "$(mktemp -d)" &&
  OS="$(uname | tr '[:upper:]' '[:lower:]')" &&
  ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')" &&
  KREW="krew-${OS}_${ARCH}" &&
  curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz" &&
  tar zxvf "${KREW}.tar.gz" &&
  ./"${KREW}" install krew
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
    set_up_virtualenvwrapper
    create_sandbox_venv
    installkrew
    exit_script
}

main
