#!/bin/env zsh
echo "setup running"
export PATH="/usr/local/bin:$PATH"
exit_code=0
PROJECT_ROOT=~/profile

get_git_details() {
    vared -p "Enter email for Git setup: " -c useremail
    vared -p "Enter username for Git setup: " -c gitusername
    if [[ -z "${CI}" ]]; then
        sudo -v # Ask for the administrator password upfront
        # Keep-alive: update existing `sudo` time stamp until script has finished
        while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
    fi
}

install_homebrew() {
    which -s brew
    sudo chown -R $(whoami) /usr/local/share/zsh /usr/local/share/zsh/site-functions
    chmod u+w /usr/local/share/zsh /usr/local/share/zsh/site-functions
    if [[ $? != 0 ]]; then
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
    else
        brew update && brew upgrade
    fi
    brew doctor

}

install_brew_packages() {
    # Ensure all relevant homebrew packages are installed
    local required_packages=(
        "zsh"
        "python"
        "git"
        "dos2unix"
        "docker"
        "helm"
        "kubernetes-cli"
    )

    for package in "${required_packages[@]}"; do
        echo -n "Checking that $package is installed..."
        if brew list | grep $package; then
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

install_cask_packages() {
    # Ensure all relevant homebrew packages are installed
    local required_packages=(
        "cleanmymac"
        "dropbox"
        "franz"
        "google-chrome"
        "iterm2"
        "microsoft-excel"
        "sublime-text"
        "visual-studio-code"
        "vlc"
        "vuze"
        "webex-meetings"
    )

    for package in "${required_packages[@]}"; do
        echo -n "Checking that $package is installed..."
        if brew cask list | grep $package; then
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

environment_variables() {
    export PATH="/usr/local/opt/python/libexec/bin:/usr/local/bin:$PATH"

    # pip installs
    pip install virtualenv
    pip install virtualenvwrapper

    # make directories
    mkdir -p ~/CODE/git
    mkdir -p ~/CODE/preferences
    mkdir -p ~/CODE/sandbox
    mkdir -p ~/CODE/.devtools
    mkdir -p ~/CODE/.virtualenvs
    mkdir -p ~/CODE/.tmp/black

    # Point CODE_ROOT  to USER/CODE
    export CODE_ROOT=~/CODE
    export WORKON_HOME=$CODE_ROOT/.virtualenvs
    export PROJECT_HOME=$CODE_ROOT
    source /usr/local/bin/virtualenvwrapper.sh

    [ -f /usr/local/bin/virtualenvwrapper.sh ] && source /usr/local/bin/virtualenvwrapper.sh

    pip install --target=$CODE_ROOT/.devtools black
}

set_up_git() {
    # Create a git config and add relevent settings
    export PATH="/usr/local/bin:${PATH}"

    if [ -f $CODE_ROOT/.gitconfig ] || [ -h $CODE_ROOT/.gitconfig ]; then
        echo -n "found ~/.gitconfig, backing up to ~/.gitconfig.old..."
        mv $CODE_ROOT/.gitconfig $CODE_ROOT/.gitconfig.old
        echo "OK"
    fi

    echo -n "Creating a new Git config and adding credentials..."
    touch $CODE_ROOT/.gitconfig
    git config --global user.name $gitusername
    git config --global user.email $useremail
    git config --global core.hooksPath $PROJECT_ROOT/hooks
    git config --global include.path $PROJECT_ROOT/lib/.gitconfig
    echo "OK"
}

install_zsh_pure() {
    echo "Installing Oh My ZSH..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    export ZSH=~/.oh-my-zsh
    echo "Installing Pure..."
    git clone https://github.com/sindresorhus/pure.git "$ZSH/pure"

}

create_zshrc() {
    # Back up old and create new zshrc that sources the entrypoint
    if [ -f ~/.zshrc ]; then
        echo -n "found ~/.zshrc, backing up to ~/.zshrc.old..."
        mv ~/.zshrc ~/.zshrc.old
        echo "OK"
    fi
    echo -n "Creating zshrc in HOME..."
    echo "source $PROJECT_ROOT/entrypoint.zsh" >~/.zshrc
    cd /usr/local/share/
    sudo chmod -R 755 zsh
    sudo chown -R root:staff zsh
    echo "OK"
}

install_vscode_exts() {
    echo "Point Sublime to correct place..."
    ln -s "/Applications/Sublime Text.app/Contents/SharedSupport/bin/subl" /usr/local/bin/sublime
    export PATH=/usr/local/bin:$PATH

    echo "Downloading extensions"
    required_extensions
    echo "Editing json"
    cp -f -v ~/profile/lib/vscode-settings.json ~/Library/application\ support/Code/User/settings.json
}

copy_postmkvirtualenv() {
    echo -n "Copying postmkvirtualenv hook to $CODE_ROOT/.virtualenvs..."
    cp $PROJECT_ROOT/lib/postmkvirtualenv $CODE_ROOT/.virtualenvs/postmkvirtualenv
    echo "OK"
}

create_venv_black() {
    cd $CODE_ROOT/.devtools
    mkvirtualenv
    setvirtualenvproject
    pip install black
    deactivate
    cd $CODE_ROOT
}

create_sandbox_venv() {
    cd $CODE_ROOT/sandbox
    mkvirtualenv jupyter
    setvirtualenvproject
    pip install --upgrade pip
    pip install jupyter voila pandas requests matplotlib nb_black
    deactivate
    cd $CODE_ROOT
}

exit_script() {
    if [[ exit_code -eq 0 ]]; then
        echo "*** Fresh Install of Alex's Profile Complete! ***"
    else
        echo "FATAL - Could not install Alex's Profile :("
    fi
    echo "Press Enter to Exit..."
    read
    exit
}

main() {
    get_git_details
    install_homebrew
    install_brew_packages
    install_cask_packages
    environment_variables
    set_up_git
    install_zsh_pure
    create_zshrc
    install_vscode_exts
    copy_postmkvirtualenv
    create_venv_black
    create_sandbox_venv
    exit_script
}

main
