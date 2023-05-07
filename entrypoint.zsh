export PATH=/usr/bin:$PATH

PROJECT_ROOT=~/CODE/git/alexwi/profile

# Source shared functions and aliases
source $PROJECT_ROOT/dotfiles/.profile

# Source personal profile if it exists
if [ -f ~/personal.zsh ]; then
	source ~/personal.zsh
fi
if [ -f ~/.tokens.zsh ]; then
	source ~/.tokens.zsh
fi