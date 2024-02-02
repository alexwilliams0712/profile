#!/bin/bash

source ~/.bash_aliases
apt_upgrader
sudo apt dist-upgrade
sudo apt install update-manager-core
sudo do-release-upgrade

echo "You'll need to restart to pick up any changes"
