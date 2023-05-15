#!/bin/bash

# Step 1: Generate SSH Key Pair
email=$(git config user.email)
ssh-keygen -t ed25519 -C "$email"

# Step 2: Add SSH Key to SSH Agent
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519

# Step 3: Add Public Key to GitHub
pub_key=$(cat ~/.ssh/id_ed25519.pub)
read -p "Enter a title for the SSH key: " key_title

echo "Copy the below into https://github.com/settings/ssh/new"
cat ~/.ssh/id_ed25519.pub