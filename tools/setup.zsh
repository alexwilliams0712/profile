export PATH=/usr/bin:/usr/local/bin:$PATH
exit_code=0
PROJECT_ROOT=$USER/profile


install_homebrew () {
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)";
    brew update && brew upgrade
    brew doctor

}

install_brew_packagaes () {
    # Ensure all relevant choco packages are installed
    local required_packages=("python" "git")

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
    # Ensure all relevant choco packages are installed
    local required_packages=("iterm2" "visual-studio-code" "sublime-text" "vlc" "franz" "vuze" "cleanmymac" "dropbox" "webex-meetings" "microsoft-excel")

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

environment_variables () {
    # Check we have the relevant environmental variables
    variables=("CODE_ROOT")
    for variable in "${variables[@]}"
    do 
        if [ -z "${(P)variable}" ]; then
            echo "$variable environment variable is not defined."
            exit_code=1
            exit_script
        fi
    done

    export PATH="/usr/local/opt/python/libexec/bin:/usr/local/bin:$PATH"
    
    # pip installs
    pip install virtualenv
    pip install virtualenvwrapper
    pip install black


    # make directories
    mkdir -p $USER/CODE/git
    mkdir -p $USER/CODE/preferences
    mkdir -p $USER/CODE/sandbox
    mkdir -p $USER/CODE/.devtools
    mkdir -p $USER/CODE/.virtualenvs

    # Point CODE_ROOT  to USER/CODE
    export CODE_ROOT=$USER/CODE
    export WORKON_HOME=$CODE_ROOT/.virtualenvs
    export PROJECT_HOME=$CODE_ROOT
    source /usr/local/bin/virtualenvwrapper.sh
    

    [ -f /usr/local/bin/virtualenvwrapper.sh ] && source /usr/local/bin/virtualenvwrapper.sh
    

    
}


set_up_git () {
    # Create a git config and add relevent settings
    export PATH=/cygdrive/c/Program\ Files/Git/cmd:$PATH

    if [ -f $CODE_ROOT/.gitconfig ] || [ -h $CODE_ROOT/.gitconfig ]; then
        echo -n "found ~/.gitconfig, backing up to ~/.gitconfig.old..."
        mv $CODE_ROOT/.gitconfig $CODE_ROOT/.gitconfig.old
        echo "OK"
    fi

    echo -n "Creating a new Git config and adding credentials..."
    touch $CODE_ROOT/.gitconfig
    git config --global user.name $USERNAME
    git config --global core.hooksPath $(cygpath -m $PROJECT_ROOT)/hooks
    git config --global include.path $(cygpath -m $PROJECT_ROOT)/lib/.gitconfig
    echo "OK"
}


install_pure () {
    git clone https://github.com/sindresorhus/pure.git "$CODE_ROOT/preferences"

}


create_zshrc () {
    # Back up old and create new zshrc that sources the entrypoint
    if [ -f $USER/.zshrc ]; then
        echo -n "found ~/.zshrc, backing up to ~/.zshrc.old..."
        mv $USER/.zshrc $USER/.zshrc.old
        echo "OK"
    fi
    echo -n "Creating zshrc in HOME..."
    echo "source $PROJECT_ROOT/entrypoint.zsh" > $USER/.zshrc
    echo "OK"
}


copy_postmkvirtualenv () {
    echo -n "Copying postmkvirtualenv hook to $CODE_ROOT/.virtualenvs..."
    mkdir -p $CODE_ROOT/.virtualenvs
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
    install_brew_packagaes
    install_cask_packagaes
    environment_variables
    set_up_git
    install_pure
    create_zshrc
    copy_postmkvirtualenv
    exit_script
}

main
