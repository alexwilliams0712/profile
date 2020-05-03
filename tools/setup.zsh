export PATH=/usr/bin:/usr/local/bin:$PATH
exit_code=0
CURRENT_FILE_LOCATION=$(dirname $(realpath $0))
PROJECT_ROOT=$(readlink -m $CURRENT_FILE_LOCATION/../)


check_choco_packages () {
    # Ensure all relevant choco packages are installed
    local required_packages=("Python36" "Cygwin" "Git" "GitPersonalAccessCredentialHelper" "ConEmu" "PythonPipConfig")

    for package in "${required_packages[@]}"
    do 
        echo -n "Checking that $package is installed..."
        if choco list -lire $package | grep -q $package
        then
            echo "OK"
        else
            echo "Not Found"
            echo "Attempting $package installation..."
            choco install $package || {
                echo "Installation of $package failed. Contact ITSA."
                exit_code=1
                exit_script
            }
        fi
        done
}


environment_variables () {
    # Check we have the relevant environmental variables
    variables=("CODE_ROOT" "HOMESHARE" "USERNAME")
    for variable in "${variables[@]}"
    do 
        if [ -z "${(P)variable}" ]; then
            echo "$variable environment variable is not defined. Contact ITSA."
            exit_code=1
            exit_script
        fi
    done

    # If an E: drive exists, point CODE_ROOT there
    if [ -d "/cygdrive/e" ]; then
        export CODE_ROOT=/cygdrive/e/CODE
    fi

    echo -n "Setting HOME environment variable..."
    cmd /c "setx HOME %HOMESHARE%" >/dev/null
    export HOME=$HOMESHARE
    echo "OK"

    # Make Cygwin binaries point to home
    echo -n "Running mkpasswd and mkgroup. This may take several minutes..."
    mkpasswd -l -d > /etc/passwd
    mkgroup -l -d > /etc/group
    echo "OK"
    echo -n "Pointing Cygwin binaries to HOME..."
    local FIND_=$(echo "/home/$USERNAME:/bin/bash" | sed "s/\//\\\\\//g")
    local REPLACE_=$(echo "\\\\$HOME:\\\bin\zsh" | sed 's:\\:\\\/:g')
    sed -i "s/$FIND_/$REPLACE_/" /cygdrive/c/Cygwin/etc/passwd
    echo "OK"
}


create_venv_black () {
    echo "Creating .devtools virtual envitonment at Code Root..."
    C:/Python36/Scripts/virtualenv.exe $(cygpath -m $CODE_ROOT)/.devtools
    source $CODE_ROOT/.devtools/Scripts/activate
    pip install black
    deactivate
}


set_up_git () {
    # Create a git config and add relevent settings
    export PATH=/cygdrive/c/Program\ Files/Git/cmd:$PATH

    if [ -f $HOME/.gitconfig ] || [ -h $HOME/.gitconfig ]; then
        echo -n "found ~/.gitconfig, backing up to ~/.gitconfig.old..."
        mv $HOME/.gitconfig $HOME/.gitconfig.old
        echo "OK"
    fi

    useremail=$(powershell "\$user = Get-ADUser \$ENV:USERNAME; Write-Host \$user.Name" | tr " " .)@airain.gg

    echo -n "Creating a new Git config and adding credentials..."
    touch $HOME/.gitconfig
    git config --global user.name $USERNAME
    git config --global user.email $useremail
    git config --global core.hooksPath $(cygpath -m $PROJECT_ROOT)/hooks
    git config --global include.path $(cygpath -m $PROJECT_ROOT)/lib/.gitconfig
    echo "OK"
}


copy_conemu_settings () {
    # Put desired ConEmu settings in place
    if [ -f C:/Users/$USERNAME/AppData/Roaming/ConEmu.xml ]; then
        echo -n "Found ConEmu settings in AppData, backing up to ConEmu.xml.old..."
        mv C:/Users/$USERNAME/AppData/Roaming/ConEmu.xml C:/Users/$USERNAME/AppData/Roaming/ConEmu.xml.old  
        echo "OK"  
    fi
    echo -n "Copying ConEmu settings to AppData..."
    cp $PROJECT_ROOT/lib/conemu_settings.xml C:/Users/$USERNAME/AppData/Roaming/ConEmu.xml
    echo "OK"
}


create_zshrc () {
    # Back up old and create new zshrc that sources the entrypoint
    if [ -f $HOME/.zshrc ]; then
        echo -n "found ~/.zshrc, backing up to ~/.zshrc.old..."
        mv $HOME/.zshrc $HOME/.zshrc.old
        echo "OK"
    fi
    echo -n "Creating zshrc in HOME..."
    echo "source $PROJECT_ROOT/entrypoint.zsh" > $HOME/.zshrc
    echo "OK"
}


copy_postmkvirtualenv () {
    echo -n "Copying postmkvirtualenv hook to $CODE_ROOT/.virtualenvs..."
    mkdir -p $CODE_ROOT/.virtualenvs
    cp $PROJECT_ROOT/lib/postmkvirtualenv $CODE_ROOT/.virtualenvs/postmkvirtualenv
    echo "OK"
}


exit_script () {
    if [[ exit_code -eq 0 ]]; then
        echo "    _    _           _         ____             __ _ _       "
        echo "   / \  (_)_ __ __ _(_)_ __   |  _ \ _ __ ___  / _(_) | ___  "
        echo "  / _ \ | | '__/ _' | | '_ \  | |_) | '__/ _ \| |_| | |/ _ \ "
        echo " / ___ \| | | | (_| | | | | | |  __/| | | (_) |  _| | |  __/ "
        echo "/_/   \_\_|_|  \__,_|_|_| |_| |_|   |_|  \___/|_| |_|_|\___| "
        echo "                                                            ...is now installed!"
    else
        echo "FATAL - Could not install Airain Profile :("
    fi
    echo "Press Enter to Exit..."
    read
    exit
}

main () {
    check_choco_packages
    environment_variables
    create_venv_black
    set_up_git
    copy_conemu_settings
    create_zshrc
    copy_postmkvirtualenv
    exit_script
}

main
