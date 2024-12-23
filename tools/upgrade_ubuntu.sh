#!/bin/bash

arrow_menu() {
    local options=("$@")
    local selected=0
    local key

    # Clear screen and hide cursor
    # clear
    tput civis
    
    echo "Please select the upgrade type (default is LTS):"
    echo
    echo
    
    while true; do
        # Clear previous menu
        echo -en "\033[${#options[@]}A"
        
        for i in ${!options[@]}; do
            if [ $i -eq $selected ]; then
                echo -e "\033[1m> ${options[$i]}\033[0m"
            else
                echo "  ${options[$i]}"
            fi
        done

        read -rsn1 key
        if [[ $key == $'\x1b' ]]; then
            read -rsn2 key
            case $key in
                '[A') ((selected--)); [ $selected -lt 0 ] && selected=$((${#options[@]}-1)) ;;
                '[B') ((selected++)); [ $selected -ge ${#options[@]} ] && selected=0 ;;
            esac
        elif [[ $key == '' ]]; then
            tput cnorm
            return $selected
        fi
    done
}

options=("LTS" "Normal")
arrow_menu "${options[@]}"
selection=$?

# Set upgrade type based on selection
upgrade_type=${options[$selection],,}

# Rest of your original script...
sudo sed -i "s/^Prompt=.*/Prompt=$upgrade_type/" /etc/update-manager/release-upgrades
echo "Upgrade type set to ${upgrade_type^}."

source ~/.bash_aliases
apt_upgrader
sudo apt dist-upgrade
sudo apt install update-manager-core
sudo do-release-upgrade -d

echo -e "\n*** Upgrade process completed. ***"
echo "You may need to restart your system to apply changes."