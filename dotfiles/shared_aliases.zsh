# Allow modification without restarting terminal
alias refresh='source ~/.zshrc'
alias reload='refresh'

# Global alias - ZSH trick - Handy way to silent any verbose command, just append 'quiet' to it
alias -g QUIET='> /dev/null 2>&1 &'

# Make grep always show color and enable Regex, which is normally a default behavior on Linux
alias grep='grep --color=auto -E'

# Open a Windows explorer in the current dir
alias explore='explorer .'

##
# LS ALIASES
##
alias ls='ls -F'
alias l='ls -c'                # show most recent files first
alias la='ls -A'               # show all (including '.files', exluding ./ and ../)
alias ll='ls -lAh'             # show all as a list sorted alphabetically
alias llf='ll | grep -vE "^d"' # ll files only
alias lt='ls -lArth'           # show all as a list sorted by reversed modification time

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
	\tail -f $@ | sed 's/\x1/|/g'
}

##
# EDITORS
##

# VSCode
code() { VSCODE_CWD="$PWD" open -n -b "com.microsoft.VSCode" --args $*; }

# Sublime Text
st() { sublime & }

##
#general
##
alias gohome="cd $CODE_ROOT"

##
#Python Dev
##
alias allinstalls="pip install -r requirements.txt; pip install -r requirements-dev.txt"
alias pylint="python -m pylint **/*.py --exit-zero"
alias pip-compile-dev="pip-compile --no-index --no-emit-trusted-host --output-file requirements-dev.txt requirements-dev.in"
alias mkdevreqs="echo 'pytest\npytest-cov\npylint' > requirements-dev.in \
                && pip-compile-dev \
                && touch requirements.in \
                && pip-compile \
                && allinstalls"
alias pytest="pytest -s -vv"
alias jnb="jupyter notebook --VoilaConfiguration.enable_nbextensions=True"
alias setvirtualenvproject="setvirtualenvproject \
                            && python -m pip install pip --upgrade \
                            && pip install setuptools pip-tools --upgrade"
alias b="black"

##
#git
##
alias gitthefuckout="git reset HEAD --hard; git clean -fd; git pull --all"
alias multipull="gohome \
                  && cd git/SalterCapital \
                  && find . -mindepth 1 -maxdepth 1 -type d -print -exec git -C {} pull \;"
alias newprofile="gohome \
                  && cd git/alexwi/profile \
                  && gitthefuckout \
                  && dos2unix tools/setup.zsh dotfiles/shared_aliases.zsh dotfiles/shared_profile.zsh \
                  && source tools/setup.zsh \
                  && reload"

##
#Kubernetes/Docker
##
alias killdeadpods="kubectl get pods --all-namespaces \
                   | grep -E 'CrashLoopBackOff|ImagePullBackOff|ErrImagePull|Terminating|Error' \
                   | awk '{print \$2 \" -n \" \$1}' \
                   | xargs kubectl delete pods --force"

alias dockerkillall="docker kill $'(docker ps -qa)'; docker rm $'(docker ps -qa)'"
alias dockerrabbit="docker run -p 5672:5672 -p 15672:15672  --network dev --hostname rabbit --name rabbit -d rabbitmq:3.8.16-management"
alias dockerredis="docker run -p 6379:6379 --name redis --network dev -d redis"
alias dockermaria="docker run -p 3306:3306  --name mariadb -e MARIADB_ROOT_PASSWORD=salcap --network dev -d mariadb"
alias dockerkubectl="kubectl --context docker-desktop"
