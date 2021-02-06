export PATH=/usr/bin:$PATH

PROJECT_ROOT=~/CODE/git/alexwi/profile

# Source shared functions and aliases
source $PROJECT_ROOT/dotfiles/shared_profile.zsh
source $PROJECT_ROOT/dotfiles/shared_aliases.zsh

# Source personal profile if it exists
if [ -f ~/personal.zsh ]; then
    source ~/personal.zsh
fi

figlet Alexs Profile
