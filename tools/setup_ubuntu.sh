#!/bin/bash
echo "Setup running"

mkdir -p "$HOME/CODE"
export PATH="$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:$PATH"
PROFILE_DIR="$(pwd)"
ARCHITECTURE="$(dpkg --print-architecture)"
export PROFILE_DIR ARCHITECTURE
set -e
set -o pipefail

source "$PROFILE_DIR/tools/common.sh"
trap 'handle_error $LINENO' ERR

# Prompt for sudo once, then keep the timestamp warm for the whole install.
keep_sudo_alive

copy_dotfiles() {
	mkdir -p "$HOME/.config/terminator"
	cp "$PROFILE_DIR/dotfiles/terminal_config" "$HOME/.config/terminator/config"
	mkdir -p "$HOME/.config/ghostty"
	cp "$PROFILE_DIR/dotfiles/ghostty/config" "$HOME/.config/ghostty/config"
	mkdir -p "$HOME/.config/gtk-3.0"
	cp "$PROFILE_DIR/dotfiles/gtk.css" "$HOME/.config/gtk-3.0/gtk.css"
	copy_shared_dotfiles
}
install_apt_packages() {
	apt_upgrader
	log "Running installs"
	sudo apt-get install -y software-properties-common
	sudo add-apt-repository -y universe
	sudo apt-get -o DPkg::Lock::Timeout=60 install -y --upgrade \
		apt-transport-https \
		aptitude \
		at \
		bash \
		bat \
		blueman \
		bpytop \
		build-essential \
		ca-certificates \
		clamav \
		clamav-daemon \
		curl \
		dos2unix \
		fail2ban \
		fd-find \
		figlet \
		flatpak \
		fswebcam \
		gcc \
		git \
		gnupg \
		gnuplot \
		hyperfine \
		imagemagick \
		jq \
		libbz2-dev \
		libdbus-1-dev \
		libffi-dev \
		libfuse2 \
		liblzma-dev \
		libmysqlclient-dev \
		libncursesw5-dev \
		libnetfilter-queue1 \
		libpq-dev \
		libreadline-dev \
		libsqlite3-dev \
		libssl-dev \
		libxml2-dev \
		libxmlsec1-dev \
		libwxgtk3.2-dev \
		llvm \
		lsd \
		lsb-release \
		lzma \
		m4 \
		make \
		mold \
		moreutils \
		net-tools \
		nfs-common \
		openssl \
		openssh-server \
		pgformatter \
		pkg-config \
		postgresql-common \
		python3-pip \
		redis-tools \
		ripgrep \
		samba \
		shellcheck \
		steam-devices \
		systemd-timesyncd \
		terminator \
		tk-dev \
		tree \
		vlc \
		wget \
		xz-utils \
		zlib1g-dev

	sudo systemctl disable postgresql.service
	sudo YES=yes /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh
	sudo apt install -y postgresql-18
	sudo systemctl enable systemd-timesyncd
	sudo systemctl start systemd-timesyncd
	sudo timedatectl set-ntp true
}

install_slack() {
	# Only handle x86_64 / amd64
	if [ "$ARCHITECTURE" = "arm64" ]; then
		echo "Skipping Slack install on arm64."
		return 0
	fi
	local DOWNLOAD_PAGE="https://slack.com/downloads/instructions/linux?ddl=1&build=deb"
	log "Fetching Slack download page..."
	local SLACK_DEB_URL
	SLACK_DEB_URL="$(
		curl -fsSL "$DOWNLOAD_PAGE" |
			grep -oE 'https://downloads\.slack-edge\.com/desktop-releases/linux/x64/[^"]+\.deb' |
			head -n1
	)"
	if [ -z "$SLACK_DEB_URL" ]; then
		log "ERROR: Could not find Slack .deb URL on $DOWNLOAD_PAGE" >&2
		return 1
	fi
	log "Detected Slack package: $SLACK_DEB_URL"
	# Download to a temp file
	local TMP_DEB
	TMP_DEB="$(mktemp /tmp/slack-desktop-XXXXXX.deb)"
	log "Downloading Slack to $TMP_DEB..."
	wget -q -O "$TMP_DEB" "$SLACK_DEB_URL"
	log "Installing / upgrading Slack..."
	sudo apt install -y "$TMP_DEB"
	log "Cleaning up..."
	rm -f "$TMP_DEB"
	log "Slack install/upgrade complete."
}

ssh_stuff() {
	sudo systemctl enable fail2ban
	sudo systemctl start fail2ban
	sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
	sudo sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
	sudo systemctl restart ssh
}

configure_remote_unlock() {
	local sudoers_file="/etc/sudoers.d/remote-unlock"
	local sudoers_rule="$USER ALL=(root) NOPASSWD: /usr/bin/loginctl unlock-sessions"
	local temp_file
	temp_file=$(mktemp)

	printf '%s\n' "$sudoers_rule" >"$temp_file"
	chmod 0440 "$temp_file"
	sudo visudo -cf "$temp_file"

	if sudo cmp -s "$temp_file" "$sudoers_file"; then
		rm -f "$temp_file"
		return
	fi

	sudo install -o root -g root -m 0440 "$temp_file" "$sudoers_file"
	rm -f "$temp_file"
}

install_pg_formatter() {
	echo "Installing pg_formatter..."

	# Install dependencies
	sudo apt update
	sudo apt install -y git perl make

	# Create temporary directory
	TEMP_DIR=$(mktemp -d)
	cd "$TEMP_DIR"

	# Clone and install
	git clone https://github.com/darold/pgFormatter.git
	cd pgFormatter
	perl Makefile.PL
	make
	sudo make install

	# Clean up
	cd ~
	rm -rf "$TEMP_DIR"

	# Verify installation
	if pg_format --version >/dev/null 2>&1; then
		echo "pg_formatter installed successfully!"
	else
		echo "pg_formatter installation may have failed. Please check manually."
		return 1
	fi
}

install_flatpaks() {
	flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
	for app in \
		org.telegram.desktop \
		org.openrgb.OpenRGB \
		org.mozilla.Thunderbird \
		com.spotify.Client \
		com.rtosta.zapzap \
		org.remmina.Remmina \
		com.sublimetext.three \
		com.valvesoftware.Steam \
		us.zoom.Zoom; do
		log "Looking for $app"
		if flatpak install --user --or-update -y flathub $app; then
			log "Successfully installed $app"
		else
			log "Failed to install $app - continuing with next application"
		fi
	done

	# ZapZap is sandboxed and only sees XDG dirs by default; grant access to
	# $HOME so it can attach and save files anywhere in the home directory.
	flatpak override --user --filesystem=home com.rtosta.zapzap
}

install_browser() {
	# Update package lists first
	log "Updating package lists"
	sudo apt update

	# Try to get the latest version from Vivaldi's download page
	log "Fetching latest Vivaldi version information"
	latest_version=$(curl -s "https://vivaldi.com/download/" | grep -o 'vivaldi-stable_[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*-[0-9]*' | head -1 | sed 's/vivaldi-stable_//')

	# Fallback to your specified version if we can't fetch the latest
	if [ -z "$latest_version" ]; then
		log "Could not fetch latest version, using fallback version"
		version="7.4.3684.52-1"
	else
		version="$latest_version"
		log "Latest version found: $version"
	fi

	if command -v vivaldi >/dev/null 2>&1; then
		installed_version=$(vivaldi --version 2>/dev/null | grep -o '[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*')
		# Strip the package revision (e.g. -1) from version for comparison
		latest_upstream=$(echo "$version" | sed 's/-[0-9]*$//')
		if [ "$installed_version" = "$latest_upstream" ]; then
			log "Vivaldi is already up to date ($installed_version)"
			return 0
		fi
		log "Vivaldi $installed_version is installed, upgrading to $latest_upstream"
	fi

	if [ "$ARCHITECTURE" = "arm64" ]; then
		arch="arm64"
	else
		arch="amd64"
	fi

	log "Downloading Vivaldi $version for $arch"
	wget "https://downloads.vivaldi.com/stable/vivaldi-stable_${version}_${arch}.deb"

	# Use dpkg to force installation of the local .deb file
	log "Installing Vivaldi from local .deb file"
	sudo dpkg -i ./vivaldi-stable_${version}_${arch}.deb

	# Fix any dependency issues that dpkg couldn't resolve
	sudo apt install -f -y

	rm -f vivaldi-stable_${version}_${arch}.deb
	log "Vivaldi installation completed"
}

install_vscode() {
	# Clean up any existing Microsoft repository configurations to prevent conflicts
	sudo rm -f /etc/apt/sources.list.d/*microsoft* /etc/apt/sources.list.d/*vscode*

	# Set up Microsoft repository (safe to run even if already configured)
	wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor >packages.microsoft.gpg
	sudo install -D -o root -g root -m 644 packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg
	sudo sh -c 'echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] \
		https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'

	# Update package lists and install/upgrade VS Code
	apt_upgrader
	sudo apt-get install -y code

	# Clean up
	rm -f packages.microsoft.gpg

	VSCODE_USER_DIR="$HOME/.config/Code/User"
	configure_vscode
}

install_1password() {
	if command -v 1password >/dev/null 2>&1; then
		log "1password is already installed, skipping installation"
		return 0
	fi
	if [ "$ARCHITECTURE" = "arm64" ]; then
		log "Downloading 1Password for ARM64"
		curl -sSO https://downloads.1password.com/linux/tar/stable/aarch64/1password-latest.tar.gz
		curl -sSO https://downloads.1password.com/linux/tar/stable/aarch64/1password-latest.tar.gz.sig
	else
		log "Downloading 1Password for x86_64"
		curl -sSO https://downloads.1password.com/linux/tar/stable/x86_64/1password-latest.tar.gz
		curl -sSO https://downloads.1password.com/linux/tar/stable/x86_64/1password-latest.tar.gz.sig
	fi

	# Verify GPG signature (optional but recommended)
	curl -sS https://downloads.1password.com/linux/keys/1password.asc | gpg --import
	gpg --verify 1password-latest.tar.gz.sig 1password-latest.tar.gz || {
		log "GPG verification failed"
		return 1
	}

	# Extract and install
	sudo tar -xf 1password-latest.tar.gz
	sudo mkdir -p /opt/1Password
	sudo mv 1password-*/* /opt/1Password/
	sudo /opt/1Password/after-install.sh

	# Clean up downloaded files
	sudo rm -f 1password-latest.tar.gz 1password-latest.tar.gz.sig
	sudo rm -rf 1password-*/

	# Verify installation
	if command -v 1password >/dev/null 2>&1; then
		log "1Password installed successfully"
		1password --version
	else
		log "1Password installation failed"
		return 1
	fi
}

install_speedtest() {
	# Ookla's packagecloud repo lags Ubuntu releases, so install the static binary directly.
	if [ "$ARCHITECTURE" = "arm64" ]; then
		local arch="aarch64"
	else
		local arch="x86_64"
	fi
	local url="https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-${arch}.tgz"
	local tmp
	tmp="$(mktemp -d)"
	log "Downloading Ookla speedtest CLI ($arch)"
	curl -fsSL "$url" | tar xz -C "$tmp"
	sudo install -m 0755 "$tmp/speedtest" /usr/local/bin/speedtest
	rm -rf "$tmp"
	speedtest --version | head -1
}

install_go() {
	arch=$(uname -m)
	case "$arch" in
	x86_64 | amd64) go_arch=linux-amd64 ;;
	aarch64 | arm64) go_arch=linux-arm64 ;;
	*)
		echo "unsupported arch: $arch" >&2
		return 1
		;;
	esac

	# get downloads page without piping curl
	page=$(curl -fsSL https://go.dev/dl/) || return 1

	t=$(grep -oEm1 "go[0-9.]+\.${go_arch}\.tar\.gz" <<<"$page") || {
		echo "could not determine latest Go version" >&2
		return 1
	}

	tmp=$(mktemp /tmp/go.tar.gz.XXXXXX) || return 1
	curl -fsSL "https://go.dev/dl/$t" -o "$tmp" || {
		rm -f "$tmp"
		return 1
	}

	sudo rm -rf /usr/local/go || {
		rm -f "$tmp"
		return 1
	}
	sudo tar -C /usr/local -xzf "$tmp" || {
		rm -f "$tmp"
		return 1
	}
	rm -f "$tmp"

	export PATH="/usr/local/go/bin:$PATH"
	go version || return 1

	go install github.com/dim13/otpauth@latest
	go install github.com/boyter/scc/v3@latest
}

install_jetbrains_toolbox() {
	source tools/jetbrains_toolbox_installer.sh
}

install_espanso() {
	# Upstream Wayland .deb is amd64-only.
	if [ "$ARCHITECTURE" != "amd64" ]; then
		log "espanso Wayland .deb is amd64-only (got: $ARCHITECTURE) — skipping"
		return 0
	fi

	local latest installed
	latest=$(curl -fsSL https://api.github.com/repos/espanso/espanso/releases/latest |
		grep -o '"tag_name": *"[^"]*"' | head -1 | cut -d'"' -f4)
	latest="${latest:-v2.3.0}"
	installed=$(command -v espanso >/dev/null && echo "v$(espanso --version 2>/dev/null)")

	if [ "$installed" != "$latest" ]; then
		log "Installing espanso $latest for Wayland (have: ${installed:-none})"
		sudo apt-get update
		sudo apt-get install -y wl-clipboard libxkbcommon0
		local deb=/tmp/espanso-wayland.deb
		curl -fsSL "https://github.com/espanso/espanso/releases/download/${latest}/espanso-debian-wayland-amd64.deb" -o "$deb" || {
			log "Failed to download espanso .deb"
			return 1
		}
		sudo dpkg -i "$deb" || sudo apt-get install -y -f
		rm -f "$deb"
	else
		log "espanso $installed already installed"
	fi

	# Grant the keyboard-capture capability and register the service on EVERY
	# run, not just on fresh install. espanso on Wayland needs CAP_DAC_OVERRIDE
	# to read /dev/input/event* (detection) and write /dev/uinput (injection);
	# without it the daemon starts but silently never expands. apt upgrades
	# strip file capabilities, and a machine where espanso was already present
	# never had it applied, so this must be reasserted idempotently.
	if ! getcap "$(command -v espanso)" 2>/dev/null | grep -q cap_dac_override; then
		log "Granting cap_dac_override to espanso (needed for keyboard capture on Wayland)"
		sudo setcap "cap_dac_override+p" "$(command -v espanso)"
	fi
	espanso service register || true

	# Reapply config every run so git-config substitutions and template edits stay in sync.
	local cfg
	cfg="$(espanso path config)"
	mkdir -p "$cfg/match"
	cp "$PROFILE_DIR/dotfiles/espanso_match_file.yml" "$cfg/match/base.yml"
	# Clipboard backend avoids Wayland keystroke quirks (e.g. @ → ").
	sed -i 's/^# backend: Clipboard/backend: Clipboard/' "$cfg/config/default.yml"

	# espanso cannot auto-detect the keyboard layout on Wayland; set it
	# explicitly (otherwise triggers/expansions can mis-map keys, e.g. @ <-> ").
	# Append once, idempotently, leaving the rest of the generated template intact.
	local kb_layout
	kb_layout=$(localectl status 2>/dev/null | sed -n 's/.*X11 Layout: *//p' | awk '{print $1}')
	if [ -n "$kb_layout" ] && ! grep -q '^keyboard_layout:' "$cfg/config/default.yml"; then
		printf '\nkeyboard_layout:\n  layout: "%s"\n' "$kb_layout" >>"$cfg/config/default.yml"
	fi

	sed -i "s|__EMAIL__|$(git config --global user.email)|;
		s|__GIT_USER__|$(git config --global user.name)|;
		s|__PHONE__|$(git config --global user.phonenumber)|" "$cfg/match/base.yml"

	# (Re)start so a running worker picks up the capability and refreshed config.
	if espanso service status 2>/dev/null | grep -q "is running"; then
		espanso service restart
	else
		espanso service start
	fi
}

install_and_setup_docker() {
	sudo mkdir -m 0755 -p /etc/apt/keyrings
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --yes --dearmor -o /etc/apt/keyrings/docker.gpg
	echo \
		"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
	sudo chmod a+r /etc/apt/keyrings/docker.gpg
	apt_upgrader
	sudo apt-get -o DPkg::Lock::Timeout=60 install -y \
		docker-ce \
		docker-ce-cli \
		containerd.io \
		docker-buildx-plugin \
		docker-compose-plugin
	sudo systemctl enable --now docker.service
	if ! grep -q "^docker:" /etc/group; then
		sudo groupadd docker
	fi
	if ! groups $USER | grep -q "\bdocker\b"; then
		sudo usermod -aG docker $USER
		# Use sg instead of newgrp - it runs the command in a new group context without starting a new shell
		sg docker -c "echo 'Docker group permissions applied for this session'"
	fi
	log "Docker setup complete"
}

install_syncthing() {
	# Syncthing via the official apt repo (apt.syncthing.net) — NOT snap.
	# Snap's confinement sandboxes ~/ and breaks syncing arbitrary folders, and
	# we avoid snap on Ubuntu generally. This mirrors the gh/docker keyring +
	# sources.list pattern used elsewhere in this script.
	sudo mkdir -p /etc/apt/keyrings
	sudo curl -fsSL -o /etc/apt/keyrings/syncthing-archive-keyring.gpg https://syncthing.net/release-key.gpg
	echo "deb [signed-by=/etc/apt/keyrings/syncthing-archive-keyring.gpg] https://apt.syncthing.net/ syncthing stable" |
		sudo tee /etc/apt/sources.list.d/syncthing.list >/dev/null
	apt_upgrader
	sudo apt-get -o DPkg::Lock::Timeout=60 install -y syncthing

	# Run as a per-user service and keep it alive across logouts/reboots so
	# folders (e.g. ~/dotfiles) stay in sync headlessly. enable-linger lets the
	# user manager run without an active login session. Guarded because
	# `systemctl --user` needs a user DBus, which may be absent over plain SSH.
	sudo loginctl enable-linger "$USER" || log "Could not enable linger for $USER"
	if systemctl --user enable --now syncthing.service 2>/dev/null; then
		log "syncthing.service enabled for $USER"
	else
		log "Could not enable syncthing user service now (no user session?); it will start on next login"
	fi
	syncthing --version | head -1 || true
}

install_github_cli() {
	log "Running gh-cli setup"
	curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg |
		sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
	sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
	echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] \
		https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
	apt_upgrader
	sudo apt -o DPkg::Lock::Timeout=60 install gh -y
}

install_clam_av() {
	sudo systemctl stop clamav-freshclam.service
	sudo freshclam
	sudo systemctl --system daemon-reload
	sudo systemctl restart clamav-daemon.service
}

install_carapace() {
	local arch
	if [ "$ARCHITECTURE" = "arm64" ]; then
		arch="arm64"
	else
		arch="amd64"
	fi
	local latest_version
	latest_version=$(curl -fsSL https://api.github.com/repos/carapace-sh/carapace-bin/releases/latest | grep -o '"tag_name": *"[^"]*"' | cut -d'"' -f4)
	if [ -z "$latest_version" ]; then
		log "Could not fetch latest carapace version"
		return 1
	fi
	local version_num="${latest_version#v}"
	local download_url="https://github.com/carapace-sh/carapace-bin/releases/download/${latest_version}/carapace-bin_${version_num}_linux_${arch}.tar.gz"
	log "Downloading carapace ${latest_version} for ${arch}"
	curl -fsSL "$download_url" -o /tmp/carapace.tar.gz
	tar -xzf /tmp/carapace.tar.gz -C /tmp
	sudo mv /tmp/carapace /usr/local/bin/carapace
	sudo chmod +x /usr/local/bin/carapace
	rm -f /tmp/carapace.tar.gz
	carapace --version
}

install_viddy() {
	local arch
	if [ "$ARCHITECTURE" = "arm64" ]; then
		arch="arm64"
	else
		arch="x86_64"
	fi
	local latest_version
	latest_version=$(curl -fsSL https://api.github.com/repos/sachaos/viddy/releases/latest | grep -o '"tag_name": *"[^"]*"' | cut -d'"' -f4)
	if [ -z "$latest_version" ]; then
		log "Could not fetch latest viddy version"
		return 1
	fi
	local download_url="https://github.com/sachaos/viddy/releases/download/${latest_version}/viddy-${latest_version}-linux-${arch}.tar.gz"
	log "Downloading viddy ${latest_version} for ${arch}"
	curl -fsSL "$download_url" -o /tmp/viddy.tar.gz
	tar -xzf /tmp/viddy.tar.gz -C /tmp
	sudo mv /tmp/viddy /usr/local/bin/viddy
	sudo chmod +x /usr/local/bin/viddy
	rm -f /tmp/viddy.tar.gz
	viddy --version
}

install_duf() {
	local arch
	if [ "$ARCHITECTURE" = "arm64" ]; then
		arch="arm64"
	else
		arch="amd64"
	fi
	local latest_version
	latest_version=$(curl -fsSL https://api.github.com/repos/muesli/duf/releases/latest | grep -o '"tag_name": *"[^"]*"' | cut -d'"' -f4)
	if [ -z "$latest_version" ]; then
		log "Could not fetch latest duf version"
		return 1
	fi
	local version_num="${latest_version#v}"
	local deb_file="duf_${version_num}_linux_${arch}.deb"
	local download_url="https://github.com/muesli/duf/releases/download/${latest_version}/${deb_file}"
	log "Downloading duf ${latest_version} for ${arch}"
	curl -fsSL "$download_url" -o "/tmp/${deb_file}"
	sudo dpkg -i "/tmp/${deb_file}"
	rm -f "/tmp/${deb_file}"
	duf --version
}

configure_gnome() {
	# One-shot GNOME interface tweaks. Persistent in dconf, so this only
	# needs to run at machine setup — not on every shell start.
	if command -v gsettings >/dev/null 2>&1; then
		gsettings set org.gnome.desktop.interface text-scaling-factor 0.95
		gsettings set org.gnome.desktop.interface cursor-size 24
		gsettings set org.gnome.desktop.interface gtk-enable-primary-paste true
	fi
}

configure_locale() {
	if ! locale -a | grep -Eiq '^en_GB\.utf-?8$'; then
		sudo locale-gen en_GB.UTF-8
	fi
	sudo update-locale LANG=en_GB.UTF-8
	if command -v gsettings >/dev/null 2>&1; then
		gsettings set org.gnome.system.locale region 'en_GB.UTF-8'
	fi
}

install_ghostty() {
	# Install / upgrade Ghostty via the mkasberg community .deb, which tracks
	# upstream releases. Asset names are suffixed with the Ubuntu VERSION_ID
	# (e.g. ghostty_1.3.1-0.ppa2_amd64_25.10.deb), not the codename, so match
	# on `lsb_release -rs`.
	local arch
	arch=$(github_arch deb)
	local ubuntu_version
	ubuntu_version=$(lsb_release -rs)
	local release_json
	release_json=$(curl -fsSL https://api.github.com/repos/mkasberg/ghostty-ubuntu/releases/latest)
	local deb_url
	deb_url=$(echo "$release_json" |
		grep -oE '"browser_download_url": *"[^"]*\.deb"' |
		cut -d'"' -f4 |
		grep "_${arch}_${ubuntu_version}\.deb$" |
		head -n1)
	if [ -z "$deb_url" ]; then
		log "Could not locate a Ghostty .deb for Ubuntu ${ubuntu_version}/${arch}"
		return 1
	fi
	log "Downloading Ghostty from $deb_url"
	github_install_deb "$deb_url"
	ghostty --version
}

install_gum() {
	sudo mkdir -p /etc/apt/keyrings
	curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --yes --dearmor -o /etc/apt/keyrings/charm.gpg
	echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list
	sudo apt update
	sudo apt install -y gum
	gum --version
}

# GitHub release helpers — shared by install_delta, install_lazygit, etc.
github_latest_tag() {
	local repo="$1"
	local tag
	tag=$(curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" | jq -r '.tag_name')
	if [ -z "$tag" ] || [ "$tag" = "null" ]; then
		log "Could not fetch latest tag for ${repo}"
		return 1
	fi
	echo "$tag"
}

github_arch() {
	# Usage: github_arch deb   -> amd64 | arm64
	#        github_arch uname -> x86_64 | arm64
	local format="${1:-deb}"
	if [ "$ARCHITECTURE" = "arm64" ]; then
		echo "arm64"
	else
		case "$format" in
		deb) echo "amd64" ;;
		uname) echo "x86_64" ;;
		esac
	fi
}

github_install_deb() {
	local url="$1"
	local deb_file="/tmp/$(basename "$url")"
	curl -fsSL "$url" -o "$deb_file"
	sudo apt install -y --reinstall "$deb_file"
	rm -f "$deb_file"
}

github_install_bin() {
	local url="$1"
	local binary_name="$2"
	local tarball="/tmp/${binary_name}.tar.gz"
	curl -fsSL "$url" -o "$tarball"
	tar -xzf "$tarball" -C /tmp "$binary_name"
	sudo mv "/tmp/$binary_name" "/usr/local/bin/$binary_name"
	sudo chmod +x "/usr/local/bin/$binary_name"
	rm -f "$tarball"
}

install_delta() {
	local version arch
	version=$(github_latest_tag "dandavison/delta") || return 1
	arch=$(github_arch deb)
	log "Downloading delta ${version} for ${arch}"
	github_install_deb "https://github.com/dandavison/delta/releases/download/${version}/git-delta_${version}_${arch}.deb"
	delta --version
}

install_lazygit() {
	local version version_num arch
	version=$(github_latest_tag "jesseduffield/lazygit") || return 1
	version_num="${version#v}"
	arch=$(github_arch uname)
	log "Downloading lazygit ${version} for ${arch}"
	github_install_bin "https://github.com/jesseduffield/lazygit/releases/download/${version}/lazygit_${version_num}_Linux_${arch}.tar.gz" lazygit
	lazygit --version
}

install_lazydocker() {
	local version version_num arch
	version=$(github_latest_tag "jesseduffield/lazydocker") || return 1
	version_num="${version#v}"
	arch=$(github_arch uname)
	log "Downloading lazydocker ${version} for ${arch}"
	github_install_bin "https://github.com/jesseduffield/lazydocker/releases/download/${version}/lazydocker_${version_num}_Linux_${arch}.tar.gz" lazydocker
	lazydocker --version
}

install_dust() {
	local version version_num arch
	version=$(github_latest_tag "bootandy/dust") || return 1
	version_num="${version#v}"
	arch=$(github_arch deb)
	log "Downloading dust ${version} for ${arch}"
	github_install_deb "https://github.com/bootandy/dust/releases/download/${version}/du-dust_${version_num}-1_${arch}.deb"
	dust --version
}

install_redis_insight() {
	if [ "$ARCHITECTURE" = "arm64" ]; then
		log "Redis Insight .deb not available for arm64, skipping"
		return 0
	fi
	local version
	version=$(github_latest_tag "redis/RedisInsight") || return 1
	local installed_version
	installed_version=$(dpkg-query -W -f='${Version}' redisinsight 2>/dev/null || echo "")
	if [ "$installed_version" = "$version" ]; then
		log "Redis Insight ${version} already installed, skipping"
		return 0
	fi
	# Purge first to avoid the prerm script wiping files during upgrade
	if [ -n "$installed_version" ]; then
		log "Purging old Redis Insight ${installed_version}"
		sudo dpkg --purge redisinsight
	fi
	log "Downloading Redis Insight ${version}"
	github_install_deb "https://github.com/redis/RedisInsight/releases/download/${version}/Redis-Insight-linux-amd64.deb"
}

install_terraform() {
	if [ "$ARCHITECTURE" = "arm64" ]; then
		arch="arm64"
	else
		arch="amd64"
	fi
	latest_version=$(curl -s https://api.github.com/repos/hashicorp/terraform/releases/latest | grep -o '\"tag_name\":.*' | cut -d'v' -f2 | tr -d \",)
	curl -sLO "https://releases.hashicorp.com/terraform/$latest_version/terraform_${latest_version}_linux_${arch}.zip"
	unzip "terraform_${latest_version}_linux_${arch}.zip"
	sudo mv terraform /usr/local/bin/
	sudo rm -rf terraform_* LICENSE.txt
	terraform version
}

install_aws_cli() {
	if [ "$ARCHITECTURE" = "arm64" ]; then
		log "Downloading AWS CLI for ARM64"
		curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"
	else
		log "Downloading AWS CLI for x86_64"
		curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
	fi

	unzip -o awscliv2.zip
	sudo ./aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update
	which aws
	aws --version
	sudo rm -rf aws*
}

install_node() {
	curl -fsSL https://deb.nodesource.com/setup_current.x | sudo -E bash -
	sudo apt-get install -y nodejs
	node -v
	npm -v
	sudo npm install -g wscat prettier json5 fracturedjsonjs
	sudo rm -f package.json package-lock.json
	sudo rm -rf node_modules
}

install_tailscale() {
	if [ -n "${SSH_CONNECTION:-}${SSH_CLIENT:-}${SSH_TTY:-}" ]; then
		log "Skipping Tailscale installation over SSH."
		return 0
	fi
	curl -fsSL https://tailscale.com/install.sh | sh
	sudo tailscale up --ssh --stateful-filtering
	sudo ufw deny ssh
}

install_font() {
	wget https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/FiraCode.zip -O FiraCode.zip
	unzip -o FiraCode.zip -d ~/.local/share/fonts
	fc-cache -fv
	rm -f FiraCode.zip
}

webinstalls() {
	curl -sS https://webi.sh/awless | sh
	curl -sS https://webi.sh/k9s | sh
	curl -sS https://webi.sh/redis-commander | sudo sh
	curl -sS https://webi.sh/shfmt | sh
	curl -sS https://webi.sh/shellcheck | sh
}

btop_install() {
	# Clone into /tmp (ephemeral and suitable for setup scripts)
	git clone https://github.com/aristocratos/btop.git /tmp/btop

	# Build and install
	cd /tmp/btop
	make
	sudo make install

	# Optional: Clean up
	rm -rf /tmp/btop
}

main() {
	collect_user_input

	failed_functions=()
	local remaining_steps=(
		set_git_config
		install_apt_packages
		ssh_stuff
		configure_remote_unlock
		install_pyenv
		install_pg_formatter
		install_browser
		install_vscode
		install_flatpaks
		install_rust
		install_foundry
		install_and_setup_docker
		install_github_cli
		install_syncthing
		install_espanso
		install_clam_av
		install_1password
		install_jetbrains_toolbox
		install_font
		btop_install
		install_slack
		install_node
		install_go
		install_tailscale
		install_aws_cli
		install_terraform
		install_speedtest
		webinstalls
		install_starship
		install_carapace
		install_viddy
		install_duf
		install_gum
		install_ghostty
		configure_locale
		configure_gnome
		install_delta
		install_lazygit
		install_lazydocker
		install_dust
		install_redis_insight
		install_ai
		apt_upgrader
	)

	# Copy the aliases before loading apt_upgrader into the parent shell.
	run_function copy_dotfiles
	# run_function isolates setup steps so failures cannot be masked. Source the
	# copied aliases in the parent as well because later steps use apt_upgrader.
	if [ -f "$HOME/.bash_aliases" ]; then
		source "$HOME/.bash_aliases"
	fi
	run_functions "${remaining_steps[@]}"

	# Report failures if any
	if [ ${#failed_functions[@]} -ne 0 ]; then
		echo -e "\n\033[1;91mThe following functions failed:\033[0m"
		printf '\033[1;91m%s\033[0m\n' "${failed_functions[@]}"
		echo -e "\n\033[1;91mPlease check the above functions and try running them individually.\033[0m"
	fi

	exit_script
}
main
