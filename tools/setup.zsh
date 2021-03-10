#!/bin/env zsh
echo "setup running"
export PATH="/usr/local/bin:$PATH"
export PATH="/opt/homebrew/sbin:$PATH"
exit_code=0
PROJECT_ROOT=~/CODE/git/alexwi/profile

install_homebrew() {
    #xcode-select --install
    which -s brew
    sudo chown -R $(whoami) /usr/local/share/zsh /usr/local/share/zsh/site-functions
    chmod u+w /usr/local/share/zsh /usr/local/share/zsh/site-functions
    if [[ $? != 0 ]]; then
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
        export PATH="/opt/homebrew/bin:$PATH"
    else
        brew update && brew upgrade
    fi
    brew doctor

}

install_brew_packages() {
    # Ensure all relevant homebrew packages are installed
    cd $PROJECT_ROOT/tools
    brew install gcc
    brew bundle install
    brew upgrade kubernetes-cli
    brew unlink kubernetes-cli && brew link kubernetes-cli
    brew upgrade hashicorp/tap/terraform
    brew link terraform
    terraform -install-autocomplete
    brew cleanup
    (
      set -x; cd "$(mktemp -d)" &&
      OS="$(uname | tr '[:upper:]' '[:lower:]')" &&
      ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')" &&
      curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/krew.tar.gz" &&
      tar zxvf krew.tar.gz &&
      KREW=./krew-"${OS}_${ARCH}" &&
      "$KREW" install krew
    )
}

environment_variables() {
    # Point CODE_ROOT  to USER/CODE
    export HOME=~/
    export CODE_ROOT=~/CODE
    export WORKON_HOME=$CODE_ROOT/.virtualenvs
    export PROJECT_HOME=$CODE_ROOT
    export PATH="/usr/local/opt/python/libexec/bin:/usr/local/bin:$PATH"
    export PATH="/usr/local/sbin:$PATH"
    export PATH="/opt/homebrew/bin:$PATH"
    export PATH=/opt/homebrew/opt/python@3.9/libexec/bin:$PATH
    export GOPATH=$HOME/golang
    export GOROOT=/usr/local/opt/go/libexec
    export GOBIN=$GOPATH/bin
    export PATH=$PATH:$GOPATH
    export PATH=$PATH:$GOROOT/bin
    export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"

    # pip installs
    pip install virtualenv --upgrade
    pip install virtualenvwrapper --upgrade
    
    # Configuration for virtualenv
    export WORKON_HOME=$CODE_ROOT/.virtualenvs
    export VIRTUALENVWRAPPER_PYTHON=/opt/homebrew/opt/python@3.9/libexec/bin/python
    export VIRTUALENVWRAPPER_VIRTUALENV=/opt/homebrew/bin/virtualenv
    source /opt/homebrew/bin/virtualenvwrapper.sh

    # make directories
    mkdir -p ~/CODE/git
    mkdir -p ~/CODE/preferences
    mkdir -p ~/CODE/sandbox
    mkdir -p ~/CODE/.devtools
    mkdir -p ~/CODE/.virtualenvs


    source /usr/local/bin/virtualenvwrapper.sh

    [ -f /usr/local/bin/virtualenvwrapper.sh ] && source /usr/local/bin/virtualenvwrapper.sh

}

set_up_git() {
    # Create a git config and add relevent settings
    export PATH="/usr/local/bin:${PATH}"

    if [ -f $CODE_ROOT/.gitconfig ] || [ -h $CODE_ROOT/.gitconfig ]; then
        echo -n "found ~/.gitconfig, backing up to ~/.gitconfig.old..."
        mv $CODE_ROOT/.gitconfig $CODE_ROOT/.gitconfig.old
        echo "OK"
    else
        vared -p "Enter email for Git setup: " -c useremail
        vared -p "Enter username for Git setup: " -c gitusername
        if [[ -z "${CI}" ]]; then
            sudo -v # Ask for the administrator password upfront
            # Keep-alive: update existing `sudo` time stamp until script has finished
            while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
        fi
    fi

    echo -n "Creating a new Git config and adding credentials..."
    touch $CODE_ROOT/.gitconfig
    git config --global user.name $gitusername
    git config --global user.email $useremail
    git config --global core.hooksPath $PROJECT_ROOT/hooks
    git config --global include.path $PROJECT_ROOT/dotfiles/.gitconfig
    echo "OK"
}

install_zsh() {
    echo "Installing Oh My ZSH..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    export ZSH=~/.oh-my-zsh
    # Gets rid of annoying prompt when quitting iterm2
    defaults write com.googlecode.iterm2 PromptOnQuit -bool false


}

vscode_setup() {
    # VS Code
    ln -sv${LINK_TARGET_EXISTS_HANDLING} "${PROJECT_ROOT}/dotfiles/vscode-settings.json" "${HOME}/Library/Application Support/Code/User/settings.json"
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
    dos2unix $PROJECT_ROOT/dotfiles/shared_profile.zsh
    dos2unix $PROJECT_ROOT/dotfiles/shared_aliases.zsh
    dos2unix $PROJECT_ROOT/entrypoint.zsh
}


copy_postmkvirtualenv() {
    echo -n "Copying postmkvirtualenv hook to $CODE_ROOT/.virtualenvs..."
    cp $PROJECT_ROOT/dotfiles/postmkvirtualenv $CODE_ROOT/.virtualenvs/postmkvirtualenv
    echo "OK"
}


create_sandbox_venv() {
    cd $CODE_ROOT/sandbox; mkvirtualenv jupyter; 
    setvirtualenvproject; 
    python3 -m pip install --upgrade pip; 
    pip install jupyter nb_black --upgrade;
#     jt -t oceans16
    deactivate
    cd $CODE_ROOT
}

setup_go() {
    GO111MODULE="on" go get sigs.k8s.io/kind@v0.3.0
    export PATH=$PATH:$(go env GOPATH)/bin
}

exit_script() {
    if [[ exit_code -eq 0 ]]; then
        source ~/.zshrc
        figlet "*** Fresh Install of Alex's Profile Complete! ***"
    else
        figlet "FATAL - Could not install Alex's Profile"
    fi
    echo "Press Enter to Exit..."
    read
    exit
}

main() {
    install_homebrew
    install_brew_packages
    environment_variables
    set_up_git
    install_zsh
    create_zshrc
    copy_postmkvirtualenv
    vscode_setup
    create_sandbox_venv
    setup_go
    
    exit_script
}

main
