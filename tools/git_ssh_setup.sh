#!/bin/bash

# Step 1: Generate SSH Key Pair
email=$(git config user.email)
ssh-keygen -t ed25519 -C "$email"

# Step 2: Add SSH Key to SSH Agent
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519

# Step 3: Add Public Key to GitHub
pub_key=$(cat ~/.ssh/id_ed25519.pub)

echo "Copy the below into https://github.com/settings/ssh/new & test with $ ssh -T git@github.com"
cat ~/.ssh/id_ed25519.pub
