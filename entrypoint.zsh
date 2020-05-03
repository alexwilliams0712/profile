export PATH=/usr/bin:$PATH

current_file_location=$(dirname $(realpath $0))

# Source shared functions and aliases
source $current_file_location/lib/shared_profile.zsh
source $current_file_location/lib/shared_aliases.zsh

# Source personal profile if it exists
if [ -f ~/personal.zsh ]; then
    source ~/personal.zsh
fi

echo "*** Airain Profile Sourced ***"
