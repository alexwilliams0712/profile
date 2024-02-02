#!/bin/bash
echo "Setup running"
mkdir -p $HOME/CODE
export CODE_ROOT=$HOME/CODE
export PROJECT_ROOT=$HOME/profile
export PATH="/usr/local/bin:$PATH"
export PATH="/usr/local/sbin:$PATH"
export PATH="$HOME/.local/bin:$PATH"
export DEFAULT_PYTHON_VERSION="3.11.2"
export PROFILE_DIR=$(pwd)
exit_code=0

copy_dotfiles() {
	# Add copy commands for your dotfiles here.
	cp $PROFILE_DIR/dotfiles/.profile $HOME/.profile
	cp $PROFILE_DIR/dotfiles/.bashrc $HOME/.bashrc
	cp $PROFILE_DIR/dotfiles/.bash_aliases $HOME/.bash_aliases
	chsh -s /bin/bash
}

install_homebrew() {
	xcode-select --install
	which -s brew
	sudo chown -R $(whoami) /usr/local/share/zsh /usr/local/share/zsh/site-functions
	chmod u+w /usr/local/share/zsh /usr/local/share/zsh/site-functions
	if [[ $? != 0 ]]; then
		/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
		export PATH="/opt/homebrew/bin:$PATH"
	else
		brew update && brew upgrade
	fi
	brew doctor

}

install_packages() {
	brew update
	brew upgrade
	brew bundle install --file=$PROFILE_DIR/Brewfile
}

setup_git() {
	# Set up global Git configuration.
	git config --global core.autocrlf false
	git config --global pull.rebase false
	git config --global http.sslVerify false
	git config --global diff.tool bc3
	git config --global color.branch auto
	git config --global color.diff auto
	git config --global color.interactive auto
	git config --global color.status auto
	git config --global push.default simple
	git config --global merge.tool kdiff3
	git config --global difftool.prompt false
	git config --global alias.c commit
	git config --global alias.ca 'commit -a'
	git config --global alias.cm 'commit -m'
	git config --global alias.cam 'commit -am'
	git config --global alias.d diff
	git config --global alias.dc 'diff --cached'
	git config --global alias.l 'log --graph --pretty=format:"%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset" --abbrev-commit'
	name=$(git config --global user.name)
	email=$(git config --global user.email)
	phone=$(git config --global user.phonenumber)
	if [ -z "$name" ]; then
		read -p "Enter github username: " name && git config --global user.name "$name"
	fi
	read -p "Enter github email address (leave blank to keep current): " new_email
	if [ ! -z "$new_email" ]; then
		git config --global user.email "$new_email"
	else
		new_email="$email"
	fi
	read -p "Enter phone number (leave blank to keep current): " new_phone
	if [ ! -z "$new_phone" ]; then
		git config --global user.phonenumber "$new_phone"
	else
		new_phone="$phone"
	fi
}

install_pyenv() {
	brew install pyenv
	pyenv update
	pyenv install -s $DEFAULT_PYTHON_VERSION
	pyenv global $DEFAULT_PYTHON_VERSION
}

install_node() {
	brew install node
	sudo npm install -g npm
	node -v
	npm -v
	npm config set prefix '~/.npm-global'
}

install_rust() {
	curl https://sh.rustup.rs -sSf | sh -s -- -y --default-toolchain stable
	source "$HOME"/.bashrc
	rustup update stable
	cargo install diesel_cli --no-default-features --features postgres
	rustup component add rustfmt clippy
	rustup update stable
}

install_jetbrains_toolbox() {
	TOOLBOX_APP="/Applications/JetBrains Toolbox.app"
	if [ ! -d "$TOOLBOX_APP" ]; then
		# Download JetBrains Toolbox
		curl -L -o jetbrains-toolbox.dmg "https://download.jetbrains.com/toolbox/jetbrains-toolbox-1.21.9712.dmg"

		# Attach the downloaded DMG file
		hdiutil attach jetbrains-toolbox.dmg

		# Copy the JetBrains Toolbox app to the /Applications folder
		cp -R "/Volumes/JetBrains Toolbox/JetBrains Toolbox.app" /Applications/

		# Detach the DMG file
		hdiutil detach "/Volumes/JetBrains Toolbox"

		# Remove the downloaded DMG file
		rm jetbrains-toolbox.dmg
	fi

	# Run JetBrains Toolbox
	open "$TOOLBOX_APP"

	CONFIG_DIR="$HOME/Library/Application Support/JetBrains"
	if [ -d "$CONFIG_DIR" ]; then
		for product_dir in "$CONFIG_DIR"/*; do
			if [ -d "$product_dir" ]; then
				mkdir -p "$product_dir/options"
				echo "Copying to $product_dir/options/watcherDefaultTasks.xml"
				cp "$PROFILE_DIR/dotfiles/watcherDefaultTasks.xml" "$product_dir/options/watcherDefaultTasks.xml"
			fi
		done
	fi
}

main() {
	setup_git
	copy_dotfiles
	install_homebrew
	install_packages
	install_pyenv
	install_node
	install_rust
	install_jetbrains_toolbox

	if [[ exit_code -eq 0 ]]; then
		cd $PROFILE_DIR
		source ~/.bashrc
		figlet "Complete"
	else
		figlet "Failed"
	fi
	echo "Press Enter to Exit..."
	read
}

main
