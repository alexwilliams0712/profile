#!/bin/bash

git fetch origin && git reset --hard origin/main
git checkout main
git pull

source tools/setup_ubuntu.sh