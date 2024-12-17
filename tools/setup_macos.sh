#!/bin/bash
echo "Setup running"
export CODE_ROOT=$HOME/CODE
export PROJECT_ROOT=$HOME/profile
export PATH="/usr/local/bin:$PATH"
export PATH="/usr/local/sbin:$PATH"
export PATH="$HOME/.local/bin:$PATH"
export DEFAULT_PYTHON_VERSION="3.12"
export PROFILE_DIR=$(pwd)
exit_code=0

set -e
set -o pipefail

handle_error() {
    echo "An error occurred on line $1"
}
trap 'handle_error $LINENO' ERR

ensure_directory() {
    cd $PROFILE_DIR
}

copy_dotfiles() {
    mkdir -p $HOME/.config
    cp $PROFILE_DIR/dotfiles/.profile $HOME/.profile
    cp $PROFILE_DIR/VERSION $HOME/BASH_PROFILE_VERSION
    cp $PROFILE_DIR/dotfiles/.bashrc $HOME/.bashrc
    cp $PROFILE_DIR/dotfiles/.bash_aliases $HOME/.bash_aliases
    
    # Setup iTerm2 preferences
    defaults write com.googlecode.iterm2 PrefsCustomFolder -string "$PROFILE_DIR/dotfiles/iterm2"
    defaults write com.googlecode.iterm2 LoadPrefsFromCustomFolder -bool true
}

install_homebrew() {
    if ! command -v brew >/dev/null 2>&1; then
        echo "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        
        # Add Homebrew to PATH for Apple Silicon Macs
        if [[ $(uname -m) == 'arm64' ]]; then
            echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> $HOME/.zprofile
            eval "$(/opt/homebrew/bin/brew shellenv)"
        fi
    fi
}

install_packages() {
    echo "Installing packages from Brewfile..."
    brew bundle --file=$PROFILE_DIR/Brewfile
}

setup_python() {
    echo "Setting up Python environment..."
    # Install Python via pyenv
    pyenv install $DEFAULT_PYTHON_VERSION -s
    pyenv global $DEFAULT_PYTHON_VERSION
    
    # Install uv using official method
    curl -LsSf https://astral.sh/uv/install.sh | sh

    # Setup uv with the current Python version
    export PYENV_ROOT="$HOME/.pyenv"
    export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init -)"
    
    # Use uv to install base packages
    uv pip install pip-tools psutil

    # Create a default venv if needed
    if [ ! -d "$HOME/.venv" ]; then
        uv venv "$HOME/.venv"
    fi
}

set_git_config() {
    git config --global core.autocrlf input
    git config --global pull.rebase false
    git config --global diff.tool bc3
    git config --global color.branch auto
    git config --global color.diff auto
    git config --global color.interactive auto
    git config --global color.status auto
    git config --global push.default simple
    git config --global difftool.prompt false
    git config --global alias.c commit
    git config --global alias.ca 'commit -a'
    git config --global alias.cm 'commit -m'
    git config --global alias.cam 'commit -am'
    git config --global alias.d diff
    git config --global alias.dc 'diff --cached'
    git config --global alias.l 'log --graph --pretty=format:"%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset" --abbrev-commit'

    name=$(git config --global user.name 2>/dev/null) || name=""
    email=$(git config --global user.email 2>/dev/null) || email=""

    if [ -z "$name" ]; then
        read -p "Enter github username: " name && git config --global user.name "$name"
    fi
    
    read -p "Enter github email address (leave blank to keep current): " new_email
    if [ ! -z "$new_email" ]; then
        git config --global user.email "$new_email"
    fi
}

setup_docker() {
    echo "Setting up Docker..."
    mkdir -p ~/.docker/cli-plugins
    ln -sfn /opt/homebrew/opt/docker-compose/bin/docker-compose ~/.docker/cli-plugins/docker-compose
    
    # Start Docker service
    open -a Docker
}

main() {
    install_homebrew
    install_packages
    copy_dotfiles
    set_git_config
    setup_python
    setup_docker
    
    echo "Setup complete!"
}

main