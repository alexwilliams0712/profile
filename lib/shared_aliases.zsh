# Allow modification without restarting cygwin
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
alias ls='ls -F --color=auto --ignore={"*.BIN","*.dll","__pyc*"}'
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


##
# DEPLOYMENT
##
alias deploy-linux='perl $DEPLOYMENT_ROOT/apps/Systems/FileManagement/Deployment/deployclient.pl -linux'
# Allows a simple use of deploy-linux by automaticlaly parsing and formating machine arguments
# Ex: deployLinuxExecSys jspalgo1 ebpalgo4
# --> deploy-linux -application ExecSysApp -application ExecSysEtc -machine jspalgo4 -machine ebpalgo4
function deployLinuxExecSys {
    # if no arguments is given, get out
    if [ ! -n "$1" ]; then
        echo "ERROR:  At least one machine name needs to be specified!\n\tIt's also possible to input multiple machine names together, separated by spaces."
        return 1
    fi
    cli='deploy-linux -application ExecSysApp -application ExecSysEtc'
    ssquery='http://servicesettings/#/services?query=ServiceType%20%3D%20Epsilon%20and%20MachineName%20in%20('
    for arg in "$@"
    do
        # for each argument, append -machine $arg to the main command line
        cli="$cli -machine $arg"
        # and append the machine name at the end of the ServiceSettings query
        ssquery="$ssquery$arg.uberit.net,"
    done
    # execute the command line
    eval "$cli"
    # prompt the machines from which Linux Epsilons was deployed in service settings
    cygstart ${ssquery%","}")"
    # clean up
    unset cli
    unset ssquery
    unset arg
}


# Quick release of prods Service Locator Keys
alias releaseSLConfigProdOnly='$DEPLOYMENT_ROOT/apps/QBS/BSG/scripts/releaseSLConfigProdOnly.sh'

# useful for gathering info on ip address
alias ddd='$DEPLOYMENT_ROOT/apps/QTG/bin/dig @uberit.net uberit.net axfr | grep -i -E'

# Submit a HBS build via QBSBuilder. The app needs to be registered in https://svn/svn/gr/Dev/trunk/etc/DevTools/airain_packages.json
build () { /cygdrive/c/Python27/python.exe $DEPLOYMENT_ROOT/apps/DT/scripts/submitBuild.py --team=IMS $@ }

# HBS Launcher - Note that its version is hard-coded, update manually here if needed / TO BE CHANGED <- FTSUP-3099
alias hbsl='$DEPLOYMENT_ROOT/apps/qbs/dt/HbsLauncher/HbsLauncher_161/bin/HbsLauncher.exe' # --hbsnoredirectoutput --hbsnoredirecterror"

# Will launch Ludgate & MoriView without CMD Prompt, thanks to the --hide argument
alias ludgate='hbsl --hbsPackage=FinTech:Ludgate --purpose=GUI.PROD -c:site GUI.PROD -c:database PROD LudgateView QUIET'
alias mori='cygstart $DEPLOYMENT_ROOT/apps/ExecSys/scripts/startMoriView.bat'


##
# CD TO USEFUL LOCATION
##
function certOUCH {
    if [ -n "$1" ];    then
        cd $(printf "//fixstaging1/log/ExecSys/Epsilon/CERTIFY/CERT/%s/OUCH/%s" "$(date +%Y%m%d)" "$1")
    else
        cd $(printf "//fixstaging1/log/ExecSys/Epsilon/CERTIFY/CERT/%s/OUCH/" "$(date +%Y%m%d)")
    fi
}
function certFIX {
    if [ -n "$1" ];    then
        cd $(printf "//fixstaging1/log/ExecSys/Epsilon/CERTIFY/CERT/%s/EPFIX/%s" "$(date +%Y%m%d)" "$1")
    else
        cd $(printf "//fixstaging1/log/ExecSys/Epsilon/CERTIFY/CERT/%s/EPFIX/" "$(date +%Y%m%d)")
    fi
}
# Grep and Tail fix logs easily by placing a separator bewtween fields
function grepcfix() {
   \grep --color=always $@ | sed 's/\x1/|/g'
}

function tailfix() {
   \tail -f  $@ | sed 's/\x1/|/g'
}

##
# SERVICES SETTINGS
##
# CERT set up, allows an optional connection name to be given. Ex "cert bamlax"
function cert {
    if [ -n "$1" ]; then
        cygstart "http://servicesettings/#/services?query=ServiceName%20~%20%5C.cert$%7Csocksprox%7C$1%20and%20ServiceName%20!~%20%5Esmd%7Cmfcert%7Cmarketfactory%7C%5Elinux%20and%20IsProd%20%3D%20False"
    else
        cygstart "http://servicesettings/#/services?query=ServiceName%20~%20%5C.cert$%7Csocksprox%20and%20ServiceName%20!~%20%5Esmd%7Cmfcert%7Cmarketfactory%7C%5Elinux%20and%20IsProd%20%3D%20False"
    fi
}
# Services to amend for monthly NSE mock test
function mocktest {
    cygstart "http://servicesettings/#/services?query=ServiceName%20~%20%22main.in%22" "http://servicesettings/#/algogroups?query=AlgoGroupName%20~%20%22smd.in.nse.*.prod%22"
    cygstart "http://servicesettings/#/algogroups?query=AlgoGroupName%20~%20%22smd.in.nse.*.prod%22"
}


##
# EDITORS
##
# BareTailPro - CLI info in http://www.baremetalsoft.com/baretailpro/usage.php?app=BareTailPro&ver=2.50aR&date=2006-11-02
bt() { /cygdrive/c/Program\ Files/Baretail/baretailpro.exe "$@" & }

# Sublime Text
st() { /cygdrive/c/Program\ Files/Sublime\ Text\ 3/sublime_text.exe "$@" & }

# Notepad++
npp() { /cygdrive/c/Program\ Files\ \(x86\)/Notepad++/notepad++.exe "$@" & }

# Beyond Compare - To show files diff- use this way: "compare file1 file2"
compare() { "$(which BComp)" "$@" & }


##
# QTG SCRIPTS
##
alias rdn='$DEPLOYMENT_ROOT/apps/QTG/scripts/rdn.exe'

mkrequirements() {
    local requirements="requirements.txt"
    echo "# $($(command -v python) --version)" > $requirements
    pip freeze >> $requirements
}


alias b=$CODE_ROOT/.devtools/Scripts/black.exe

# K8s
if [ -e /cygdrive/c/ProgramData/chocolatey/bin/kubectl-login ]; then
    alias kl="kubectl-login"
    alias k="kubectl"
    alias kas="k -n airain-staging"
    alias ka="k -n airain"
fi

# oh-my-zsh/git plugin creates an alias gcl - remove
unalias gcl &> /dev/null
gcl() {
# always clone at a structured location, can be run from anywhere in the filesystem
    if [ $# -eq 0 ]; then
        echo "gcl <repo-url> [OPTIONS] - see 'man git-clone' documentation\n"
        echo "At least one argument is required!"
        return 1
    fi
    local org_repo=$(echo "$1"  | sed 's/.*git\.uberit\.net\(\/\|\:\)\(.*\)\.git$/\2/')
    local repo_path=$CODE_ROOT/git/$org_repo
    git clone "$@" $(cygpath -m $repo_path)
    cd $repo_path
}

##
#git
##
alias multipull="cd $CODE_ROOT/git; find . -mindepth 1 -maxdepth 2 -type d -print -exec git -C {} pull --all \;"


##
#Python Dev
##
alias pylint="python -m pylint **/*.py --exit-zero"


##
#general
##
alias gohome="cd $CODE_ROOT"


echo "*** Alex's Profile Loaded ***"
