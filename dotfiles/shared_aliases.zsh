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

# Makes Python Unit tests for the user, just specify the module to create tests for

function mkpytests {
	# if no arguments given, get out
	if [ ! -n "$1" ]; then
		echo "What py file do you want to test, moron?"
		return 1
	fi
	mkdir -p tests
	touch "tests/__init__.py"
	for arg in "$@"
	do
		# For each py file specified, create a tests file
		touch "tests/test_$arg"
		if ! grep -q "import pytest" "tests/test_$arg"; then
			echo  '""""\nUnit tests to confirm $arg works entirely as expected\n"""\n# pylint: disable=redefined-outer-name\n\nimport pytest\n\n' > "tests/test_$arg"
		fi
		grep def $arg | while read -r line ;
		do
			func="$(cut -d'(' -f1 <<< "$(cut -d' ' -f2 <<< "$line")")"
			if [ "$func" != "__init__" ]; then
				if  grep -q "def test_$func" "tests/test_$arg"; then
					echo  "test_$func() already exists"
				else
					echo "def test_$func():\n	# A unit test to confirm $func function works as expected\n	assert 1 == 2\n" >> "tests/test_$arg"
				fi
			fi
		done
	done
	unset arg
	unset func
	unset line
}


##
# EDITORS
##


# VSCode
code () { VSCODE_CWD="$PWD" open -n -b "com.microsoft.VSCode" --args $* ;}

# Sublime Text
st() { sublime & }

mkrequirements() {
    local requirements="requirements.in"
    echo "# $($(command -v python) --version)" > $requirements
    pip freeze >> $requirements
}


alias b=$CODE_ROOT/.devtools/Scripts/black.exe

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
alias mkdevreqs="echo 'pytest\npytest-cov\npylint\npylint-flask\npylint-flask-sqlalchemy' > requirements-dev.in; pip-compile-dev; touch requirements.in; pip-compile; allinstalls"
alias pytest="pytest -s -vv"
alias jnb="jupyter notebook --VoilaConfiguration.enable_nbextensions=True"


##
#git
##
alias gitthefuckout="git reset HEAD --hard; git clean -fd; git pull --all"
alias multipull="gohome; cd git/SalterCapital; find . -mindepth 1 -maxdepth 1 -type d -print -exec git -C {} pull \;"
alias newprofile="gohome; cd git/alexwi/profile; gitthefuckout; dos2unix tools/setup.zsh dotfiles/shared_aliases.zsh dotfiles/shared_profile.zsh; source tools/setup.zsh; reload"


##
#K9s
##
alias trading_prod="kl; K9s --kubeconfig ~/.kube/config"
alias trading_staging="kl; K9s --kubeconfig ~/.kube/config"
alias home_automation="kl; K9s --kubeconfig ~/.kube/config"
