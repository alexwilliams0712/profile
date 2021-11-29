#!/bin/bash

echo "Setup running"

mkdir -p $HOME/CODE
export CODE_ROOT=$HOME/CODE
export PROJECT_ROOT=$HOME/profile
export PATH="/usr/local/bin:$PATH"
export PATH="/usr/local/sbin:$PATH"
export PATH="$HOME/.local/bin:$PATH"

copy_dotfiles() {
    cp $PROJECT_ROOT/dotfiles/.profile $HOME/.profile
    cp $PROJECT_ROOT/dotfiles/.bashrc $HOME/.bashrc
    cp $PROJECT_ROOT/dotfiles/.bash_aliases $HOME/.bash_aliases
    cp $PROJECT_ROOT/dotfiles/.gitconfig $HOME/.gitconfig


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
            docker-compose

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
        k9s \
        1password 

    do
       sudo snap install $i
    done
    
    snap install --candidate terraform
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

exit_script() {
    if [[ exit_code -eq 0 ]]; then
        cd $PROJECT_ROOT
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
    exit_script
}

main
