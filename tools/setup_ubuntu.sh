#!/bin/bash
echo "Setup running"

if [ "$(id -u)" -eq 0 ]; then
	printf 'Run setup as your normal user; privileged steps use sudo.\n' >&2
	exit 1
fi

# shellcheck disable=SC1091
source /etc/os-release
if [ "${ID:-}" != ubuntu ] || ! dpkg --compare-versions "${VERSION_ID:-0}" ge 24.04; then
	printf 'Linux setup requires Ubuntu 24.04 or newer.\n' >&2
	exit 1
fi

mkdir -p "$HOME/CODE"
export PATH="$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:$PATH"
PROFILE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROFILE_DIR"
ARCHITECTURE="$(dpkg --print-architecture)" || exit 1
case "$ARCHITECTURE" in
amd64 | arm64) ;;
*)
	printf 'Unsupported Ubuntu architecture: %s\n' "$ARCHITECTURE" >&2
	exit 1
	;;
esac
export PROFILE_DIR ARCHITECTURE
set -e
set -o pipefail

source "$PROFILE_DIR/tools/common.sh"
setup_progress_install_traps
trap 'setup_progress_finish; handle_error $LINENO' ERR

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
	local fuse_package=libfuse2
	if apt-cache show libfuse2t64 >/dev/null 2>&1; then
		fuse_package=libfuse2t64
	fi
	log "Running installs"
	apt_get install -y software-properties-common
	sudo add-apt-repository --no-update -y universe
	apt_get update
	apt_get install -y --upgrade \
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
		"$fuse_package" \
		liblzma-dev \
		libmysqlclient-dev \
		libncurses-dev \
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
		ufw \
		unzip \
		vlc \
		wget \
		xz-utils \
		zlib1g-dev

	sudo systemctl disable postgresql.service
	with_package_lock_retry sudo env LC_ALL=C YES=yes /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh
	apt_get install -y postgresql-18
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
	apt_get install -y "$TMP_DEB"
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

install_pg_formatter() (
	local install_dir
	install_dir=$(mktemp -d)
	trap 'rm -rf "$install_dir"' EXIT
	cd "$install_dir"
	echo "Installing pg_formatter..."

	# Install dependencies
	apt_get update
	apt_get install -y git perl make

	# Clone and install
	git clone https://github.com/darold/pgFormatter.git
	cd pgFormatter
	perl Makefile.PL
	make
	sudo make install

	# Verify installation
	if pg_format --version >/dev/null 2>&1; then
		echo "pg_formatter installed successfully!"
	else
		echo "pg_formatter installation may have failed. Please check manually."
		return 1
	fi
)

install_flatpaks() {
	local failed=0
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
			failed=1
		fi
	done

	# ZapZap is sandboxed and only sees XDG dirs by default; grant access to
	# $HOME so it can attach and save files anywhere in the home directory.
	flatpak override --user --filesystem=home com.rtosta.zapzap
	return "$failed"
}

install_browser() {
	apt_get update
	if ! apt-cache show vivaldi-stable >/dev/null 2>&1; then
		local key_file
		key_file=$(mktemp)
		curl -fsSL https://repo.vivaldi.com/stable/linux_signing_key.pub |
			gpg --dearmor >"$key_file"
		sudo install -D -m 644 "$key_file" /etc/apt/keyrings/vivaldi.gpg
		rm -f "$key_file"
		printf 'deb [arch=%s signed-by=/etc/apt/keyrings/vivaldi.gpg] https://repo.vivaldi.com/stable/deb/ stable main\n' "$ARCHITECTURE" |
			sudo tee /etc/apt/sources.list.d/vivaldi.list >/dev/null
		apt_get update
	fi
	apt_get install -y vivaldi-stable
	vivaldi --version
}

install_vscode() {
	apt_get update
	if ! apt-cache show code >/dev/null 2>&1; then
		local key_file
		key_file=$(mktemp)
		curl -fsSL https://packages.microsoft.com/keys/microsoft.asc |
			gpg --dearmor >"$key_file"
		sudo install -D -m 644 "$key_file" /etc/apt/keyrings/packages.microsoft.gpg
		rm -f "$key_file"
		printf '%s\n' 'deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main' |
			sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null
		apt_get update
	fi
	apt_get install -y code
	local VSCODE_USER_DIR="$HOME/.config/Code/User"
	configure_vscode
}

install_1password() (
	local install_dir
	install_dir=$(mktemp -d)
	trap 'rm -rf "$install_dir"' EXIT
	cd "$install_dir"
	if command -v 1password >/dev/null 2>&1; then
		log "1password is already installed, skipping installation"
		return 0
	fi
	if [ "$ARCHITECTURE" = "arm64" ]; then
		log "Downloading 1Password for ARM64"
		curl -fsSLO https://downloads.1password.com/linux/tar/stable/aarch64/1password-latest.tar.gz
		curl -fsSLO https://downloads.1password.com/linux/tar/stable/aarch64/1password-latest.tar.gz.sig
	else
		log "Downloading 1Password for x86_64"
		curl -fsSLO https://downloads.1password.com/linux/tar/stable/x86_64/1password-latest.tar.gz
		curl -fsSLO https://downloads.1password.com/linux/tar/stable/x86_64/1password-latest.tar.gz.sig
	fi

	# Verify GPG signature (optional but recommended)
	curl -fsSL https://downloads.1password.com/linux/keys/1password.asc | gpg --import
	gpg --verify 1password-latest.tar.gz.sig 1password-latest.tar.gz || {
		log "GPG verification failed"
		return 1
	}

	# Extract and install
	tar -xf 1password-latest.tar.gz
	sudo mkdir -p /opt/1Password
	sudo mv 1password-*/* /opt/1Password/
	sudo /opt/1Password/after-install.sh

	# Clean up downloaded files
	sudo rm -f 1password-latest.tar.gz 1password-latest.tar.gz.sig

	# Verify installation
	if command -v 1password >/dev/null 2>&1; then
		log "1Password installed successfully"
		1password --version
	else
		log "1Password installation failed"
		return 1
	fi
)

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

install_go() (
	local arch go_arch page archive install_dir
	arch=$(uname -m)
	case "$arch" in
	x86_64 | amd64) go_arch=linux-amd64 ;;
	aarch64 | arm64) go_arch=linux-arm64 ;;
	*)
		log "Unsupported Go architecture: $arch"
		return 1
		;;
	esac
	install_dir=$(mktemp -d)
	trap 'rm -rf "$install_dir"' EXIT
	page=$(curl -fsSL https://go.dev/dl/)
	archive=$(grep -oEm1 "go[0-9.]+\.${go_arch}\.tar\.gz" <<<"$page")
	curl -fsSL "https://go.dev/dl/$archive" -o "$install_dir/go.tar.gz"
	tar -xzf "$install_dir/go.tar.gz" -C "$install_dir"
	# Validate the replacement before removing a working installation.
	"$install_dir/go/bin/go" version
	sudo rm -rf /usr/local/go
	sudo mv "$install_dir/go" /usr/local/go
	export PATH="/usr/local/go/bin:$PATH"
	go version
	go install github.com/dim13/otpauth@latest
	go install github.com/boyter/scc/v3@latest
)

install_jetbrains_toolbox() {
	# shellcheck disable=SC1091
	source "$PROFILE_DIR/tools/jetbrains_toolbox_installer.sh"
}

install_espanso() {
	if [ "$ARCHITECTURE" != amd64 ]; then
		log "Espanso upstream .deb packages support amd64 only; skipping $ARCHITECTURE."
		return 0
	fi
	local session package other_package
	if [ -n "${WAYLAND_DISPLAY:-}" ] || [ "${XDG_SESSION_TYPE:-}" = wayland ]; then
		session=wayland
		package=espanso-wayland
		other_package=espanso
	elif [ -n "${DISPLAY:-}" ] || [ "${XDG_SESSION_TYPE:-}" = x11 ]; then
		session=x11
		package=espanso
		other_package=espanso-wayland
	else
		log "No desktop session detected; run Espanso setup from a desktop terminal."
		return 0
	fi

	local latest installed="" package_status
	latest=$(github_latest_tag espanso/espanso)
	package_status=$(dpkg-query -W -f='${db:Status-Status}' "$package" 2>/dev/null || true)
	if [ "$package_status" = installed ] && command -v espanso >/dev/null 2>&1; then
		installed="v$(espanso --version)"
	fi
	apt_get update
	if [ "$session" = wayland ]; then
		apt_get install -y wl-clipboard libxkbcommon0 libcap2-bin
	fi
	if [ "$installed" != "$latest" ]; then
		log "Installing Espanso $latest for $session (have: ${installed:-none})"
		local install_dir status=0
		local -a packages=()
		install_dir=$(mktemp -d)
		package_status=$(dpkg-query -W -f='${db:Status-Status}' "$other_package" 2>/dev/null || true)
		if [ "$package_status" = installed ]; then
			packages+=("$other_package-")
		fi
		if curl -fsSL "https://github.com/espanso/espanso/releases/download/${latest}/espanso-debian-${session}-amd64.deb" -o "$install_dir/espanso.deb"; then
			apt_get install -y "$install_dir/espanso.deb" "${packages[@]}" || status=$?
		else
			status=$?
		fi
		rm -rf "$install_dir"
		if [ "$status" -ne 0 ]; then
			return "$status"
		fi
	fi

	# Package upgrades can strip the capability needed for Wayland input access.
	if [ "$session" = wayland ] && ! getcap "$(command -v espanso)" | grep -q cap_dac_override; then
		sudo setcap 'cap_dac_override+p' "$(command -v espanso)"
	fi
	espanso service register

	local cfg kb_layout
	cfg="$(espanso path config)"
	mkdir -p "$cfg/match" "$cfg/config"
	touch "$cfg/config/default.yml"
	configure_espanso_matches "$cfg/match/base.yml"
	if [ "$session" = wayland ]; then
		if ! grep -q '^backend:' "$cfg/config/default.yml"; then
			printf '\nbackend: Clipboard\n' >>"$cfg/config/default.yml"
		fi
		kb_layout=$(localectl status 2>/dev/null | sed -n 's/.*X11 Layout: *//p' | awk '{print $1}' || true)
		if [ -n "$kb_layout" ] && ! grep -q '^keyboard_layout:' "$cfg/config/default.yml"; then
			printf '\nkeyboard_layout:\n  layout: "%s"\n' "$kb_layout" >>"$cfg/config/default.yml"
		fi
	fi
	if espanso service status 2>/dev/null | grep -q 'is running'; then
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
	apt_get install -y \
		docker-ce \
		docker-ce-cli \
		containerd.io \
		docker-buildx-plugin \
		docker-compose-plugin
	sudo systemctl enable --now docker.service
	if ! grep -q "^docker:" /etc/group; then
		sudo groupadd docker
	fi
	if ! groups "$USER" | grep -q "\bdocker\b"; then
		sudo usermod -aG docker "$USER"
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
	apt_get install -y syncthing

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
	apt_get install gh -y
}

install_clam_av() (
	sudo systemctl stop clamav-freshclam.service
	trap 'sudo systemctl start clamav-freshclam.service' EXIT
	sudo freshclam
	sudo systemctl --system daemon-reload
	sudo systemctl restart clamav-daemon.service
)

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
	github_install_bin "$download_url" carapace
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
	github_install_bin "$download_url" viddy
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
	github_install_deb "$download_url"
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
	apt_get update
	apt_get install -y gum
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

github_install_deb() (
	local url="$1" install_dir
	install_dir=$(mktemp -d) || return
	trap 'rm -rf "$install_dir"' EXIT
	curl -fsSL "$url" -o "$install_dir/package.deb" || return
	apt_get install -y --reinstall "$install_dir/package.deb"
)

github_install_bin() (
	local url="$1" binary_name="$2" install_dir
	install_dir=$(mktemp -d) || return
	trap 'rm -rf "$install_dir"' EXIT
	curl -fsSL "$url" -o "$install_dir/package.tar.gz" || return
	tar -xzf "$install_dir/package.tar.gz" -C "$install_dir" "$binary_name" || return
	sudo install -m 0755 "$install_dir/$binary_name" "/usr/local/bin/$binary_name"
)

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
		with_package_lock_retry sudo env LC_ALL=C dpkg --purge redisinsight
	fi
	log "Downloading Redis Insight ${version}"
	github_install_deb "https://github.com/redis/RedisInsight/releases/download/${version}/Redis-Insight-linux-amd64.deb"
}

install_terraform() (
	local install_dir
	install_dir=$(mktemp -d)
	trap 'rm -rf "$install_dir"' EXIT
	cd "$install_dir"
	if [ "$ARCHITECTURE" = "arm64" ]; then
		arch="arm64"
	else
		arch="amd64"
	fi
	local version
	version=$(github_latest_tag hashicorp/terraform)
	version=${version#v}
	curl -fsSL "https://releases.hashicorp.com/terraform/$version/terraform_${version}_linux_${arch}.zip" -o terraform.zip
	unzip terraform.zip
	sudo install -m 0755 terraform /usr/local/bin/terraform
	terraform version
)

install_aws_cli() (
	local install_dir
	install_dir=$(mktemp -d)
	trap 'rm -rf "$install_dir"' EXIT
	cd "$install_dir"
	if [ "$ARCHITECTURE" = "arm64" ]; then
		log "Downloading AWS CLI for ARM64"
		curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"
	else
		log "Downloading AWS CLI for x86_64"
		curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
	fi

	unzip -o awscliv2.zip
	sudo ./aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update
	which aws
	aws --version
)

run_apt_installer() (
	local installer
	installer=$(mktemp) || return
	trap 'rm -f "$installer"' EXIT
	curl -fsSL "$1" -o "$installer" || return
	with_package_lock_retry sudo env LC_ALL=C "$2" "$installer"
)

install_node() {
	run_apt_installer https://deb.nodesource.com/setup_current.x bash
	apt_get install -y nodejs
	node -v
	npm -v
	sudo npm install -g wscat prettier json5 fracturedjsonjs
}

install_tailscale() {
	if [ -n "${SSH_CONNECTION:-}${SSH_CLIENT:-}${SSH_TTY:-}" ]; then
		log "Skipping Tailscale installation over SSH."
		return 0
	fi
	run_apt_installer https://tailscale.com/install.sh sh
	sudo tailscale set --ssh --stateful-filtering
	sudo tailscale up
	sudo ufw deny ssh
}

install_font() (
	local install_dir
	install_dir=$(mktemp -d)
	trap 'rm -rf "$install_dir"' EXIT
	cd "$install_dir"
	wget https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/FiraCode.zip -O FiraCode.zip
	unzip -o FiraCode.zip -d ~/.local/share/fonts
	fc-cache -fv
	rm -f FiraCode.zip
)

webinstalls() {
	curl -sS https://webi.sh/awless | sh
	curl -sS https://webi.sh/k9s | sh
	curl -sS https://webi.sh/redis-commander | sudo sh
	curl -sS https://webi.sh/shfmt | sh
	curl -sS https://webi.sh/shellcheck | sh
}

btop_install() (
	local install_dir
	install_dir=$(mktemp -d)
	trap 'rm -rf "$install_dir"' EXIT
	git clone --depth 1 https://github.com/aristocratos/btop.git "$install_dir/btop"
	cd "$install_dir/btop"
	make
	sudo make install
)

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
	local setup_steps=(copy_dotfiles "${remaining_steps[@]}")
	setup_progress_start "${setup_steps[@]}"

	# Copy the aliases before loading apt_upgrader into the parent shell.
	run_function copy_dotfiles
	# run_function isolates setup steps so failures cannot be masked. Source the
	# copied aliases in the parent as well because later steps use apt_upgrader.
	if [ -f "$HOME/.bash_aliases" ]; then
		# shellcheck disable=SC1091
		source "$HOME/.bash_aliases"
	fi
	run_functions "${remaining_steps[@]}"
	setup_progress_finish

	# Report failures if any
	if [ ${#failed_functions[@]} -ne 0 ]; then
		echo -e "\n\033[1;91mThe following functions failed:\033[0m"
		printf '\033[1;91m%s\033[0m\n' "${failed_functions[@]}"
		echo -e "\n\033[1;91mPlease check the above functions and try running them individually.\033[0m"
	fi

	exit_script
}
main
