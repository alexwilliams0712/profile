export PATH=/usr/bin:$PATH


# Source shared functions and aliases
source ~/profile/lib/shared_profile.zsh
source ~/profile/lib/shared_aliases.zsh

# Source personal profile if it exists
if [ -f ~/personal.zsh ]; then
    source ~/personal.zsh
fi

echo "*** Alex's Profile Sourced ***"
