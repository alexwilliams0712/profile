export CODE_ROOT=$HOME/CODE
export KUBECONFIG=~/.kube/config

# Allow modification without restarting terminal
alias refresh='source ~/.bashrc'
alias reload='refresh'

# Make grep always show color and enable Regex, which is normally a default behavior on Linux
alias grep='grep --color=auto -E'

# Open a Windows explorer in the current dir
alias explore='explorer .'


##
# LS ALIASES
##
alias ls='ls -F'
alias l='ls -c'                 # show most recent files first
alias la='ls -A'                # show all (including '.files', exluding ./ and ../)
alias ll='ls -lAh'              # show all as a list sorted alphabetically
alias llf='ll | grep -vE "^d"'  # ll files only
alias lt='ls -lArth'            # show all as a list sorted by reversed modification time


##
# CD ALIASES
##
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias bk='cd $OLDPWD'

# Grep and Tail fix logs easily by placing a separator bewtween fields
function grepcfix() {
   \grep --color=always $@ | sed 's/\x1/|/g'
}

function tailfix() {
   \tail -f  $@ | sed 's/\x1/|/g'
}

# Python
alias pip-compile="sort requirements.in -o requirements.in; pip-compile"

# Sublime Text
alias st=subl

##
#general
##
alias gohome="cd $CODE_ROOT"

##
#git
##
alias gitthefuckout="git reset HEAD --hard; git clean -fd; git pull --all"
alias multipull="gohome; cd git/SalterCapital; find . -mindepth 1 -maxdepth 1 -type d -print -exec git -C {} pull \;"

##
#K8s
##
alias k9s="k9s-nsg"


##
#Certs
##
u-cert-ain='openssl req -x509 -nodes -newkey rsa:4096 -keyout key.pem -out cert.pem -sha256 -days 3650 -subj "/C=GB/ST=London/L=London/O=Maven Securities/OU=DigitalAssets/CN=DA"'
