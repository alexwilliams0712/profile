export PATH=/usr/bin:$PATH

PROJECT_ROOT=~/CODE/git/profile

# Source shared functions and aliases
source $PROJECT_ROOT/lib/shared_profile.zsh
source $PROJECT_ROOT/lib/shared_aliases.zsh

# Source personal profile if it exists
if [ -f ~/personal.zsh ]; then
    source ~/personal.zsh
fi

echo "*** Alex's Profile Sourced ***"
