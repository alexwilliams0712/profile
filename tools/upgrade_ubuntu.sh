#!/bin/bash

source ~/.bash_aliases
apt_upgrader
sudo apt dist-upgrade
sudo apt install update-manager-core
sudo do-release-upgrade -d

echo -e "\n*** Upgrade process completed. ***"
echo "You may need to restart your system to apply changes."

# Instructions for switching to development versions
cat <<EOF

To enable upgrades to development versions, run the following command:
sudo sed -i 's/^Prompt=.*/Prompt=normal/' /etc/update-manager/release-upgrades

After that, rerun this upgrade script to apply changes.
EOF
