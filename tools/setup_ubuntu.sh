#!/bin/bash

echo "Setup running"

mkdir -p $HOME/CODE
export CODE_ROOT=$HOME/CODE
export PROJECT_ROOT=$HOME/profile
export PATH="/usr/local/bin:$PATH"
export PATH="/usr/local/sbin:$PATH"

install_apt_packages() {
    sudo apt update
    # Sublime
    sudo apt install apt-transport-https ca-certificates curl software-properties-common
    sudo add-apt-repository "deb https://download.sublimetext.com/ apt/stable/"
	
    # Apt gets
    sudo apt-get install \
            python3-pip

    # Apt install
    sudo apt install \
            sublime-text \
            figlet \
            terminator

    # Snap install
    sudo snap install pycharm-professional --classic
    sudo snap install rider --classic
    sudo snap install goland --classic

}

copy_dotfiles() {
    cp $PROJECT_ROOT/dotfiles/.profile $HOME/.profile
    cp $PROJECT_ROOT/dotfiles/.bashrc $HOME/.bashrc
    cp $PROJECT_ROOT/dotfiles/.bash_aliases $HOME/.bash_aliases
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
    install_apt_packages
    copy_dotfiles
    set_up_virtualenvwrapper
    create_sandbox_venv
    
    exit_script
}

main