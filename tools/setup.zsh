#!/bin/env zsh


echo "setup running"
export PATH="/usr/local/bin:$PATH"
exit_code=0
PROJECT_ROOT=~/profile


install_homebrew () {
	which -s brew
    if [[ $? != 0 ]] ; then
    	/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)";
    else
    	brew update && brew upgrade
    fi
    brew doctor
}

install_brew_packagaes () {
    # Ensure all relevant homebrew packages are installed
    local required_packages=(
    	"python" 
    	"git"
    	)

    for package in "${required_packages[@]}"
    do 
        echo -n "Checking that $package is installed..."
        if brew list $package | grep $package
        then
            echo "OK"
        else
            echo "Not Found"
            echo "Attempting $package installation..."
            brew install $package || {
                echo "Installation of $package failed."
                exit_code=1
                exit_script
            }
        fi
        done
}


install_cask_packagaes () {
    # Ensure all relevant homebrew packages are installed
    local required_packages=(
    	"iterm2" 
    	"visual-studio-code" 
    	)

    for package in "${required_packages[@]}"
    do 
        echo -n "Checking that $package is installed..."
        if brew cask list $package | grep $package
        then
            echo "OK"
        else
            echo "Not Found"
            echo "Attempting $package installation..."
            brew cask install $package || {
                echo "Installation of $package failed."
                exit_code=1
                exit_script
            }
        fi
        done
}

environment_variables () {
    export PATH="/usr/local/opt/python/libexec/bin:/usr/local/bin:$PATH"
    
    # pip installs
    pip install virtualenv
    pip install virtualenvwrapper
    pip install black

    echo $PROJECT_ROOT
    # make directories
    cd ~
    mkdir -p ~/CODE
    mkdir -p ~/CODE/git
    mkdir -p ~/CODE/preferences
    mkdir -p ~/CODE/sandbox
    mkdir -p ~/CODE/.devtools
    mkdir -p ~/CODE/.virtualenvs

    # Point CODE_ROOT  to USER/CODE
    export CODE_ROOT=~/CODE
    export WORKON_HOME=$CODE_ROOT/.virtualenvs
    export PROJECT_HOME=$CODE_ROOT
    source /usr/local/bin/virtualenvwrapper.sh
    

    [ -f /usr/local/bin/virtualenvwrapper.sh ] && source /usr/local/bin/virtualenvwrapper.sh
    

    
}


set_up_git () {
    # Create a git config and add relevent settings
    export PATH="/usr/local/bin:${PATH}"

    if [ -f $CODE_ROOT/.gitconfig ] || [ -h $CODE_ROOT/.gitconfig ]; then
        echo -n "found ~/.gitconfig, backing up to ~/.gitconfig.old..."
        mv $CODE_ROOT/.gitconfig $CODE_ROOT/.gitconfig.old
        echo "OK"
    fi

    echo -n "Creating a new Git config and adding credentials..."
    touch $CODE_ROOT/.gitconfig
    git config --global user.name $USERNAME
    git config --global core.hooksPath $PROJECT_ROOT/hooks
    git config --global include.path $PROJECT_ROOT/lib/.gitconfig
    echo "OK"
}


install_pure () {
	echo "Installing pure..."
	mkdir -p $CODE_ROOT/preferences/pure
    git clone https://github.com/sindresorhus/pure.git "$CODE_ROOT/preferences/pure"

}


create_zshrc () {
    # Back up old and create new zshrc that sources the entrypoint
    if [ -f ~/.zshrc ]; then
        echo -n "found ~/.zshrc, backing up to ~/.zshrc.old..."
        mv ~/.zshrc ~/.zshrc.old
        echo "OK"
    fi
    echo -n "Creating zshrc in HOME..."
    echo "source $PROJECT_ROOT/entrypoint.zsh" > ~/.zshrc
    echo "OK"
}


copy_postmkvirtualenv () {
    echo -n "Copying postmkvirtualenv hook to $CODE_ROOT/.virtualenvs..."
    cp $PROJECT_ROOT/lib/postmkvirtualenv $CODE_ROOT/.virtualenvs/postmkvirtualenv
    echo "OK"
}


exit_script () {
    if [[ exit_code -eq 0 ]]; then
        echo "*** Fresh Install of Alex's Profile Complete! ***"
    else
        echo "FATAL - Could not install Alex's Profile :("
    fi
    echo "Press Enter to Exit..."
    read
    exit
}

main () {
    install_homebrew
    echo "Homebrew Installed"
    install_brew_packagaes
    install_cask_packagaes
    echo "Packages Installed"
    environment_variables
    set_up_git
    install_pure
    create_zshrc
    copy_postmkvirtualenv
    exit_script
}

main
