#!/bin/bash

# Configuration
DEFAULT_VERSION="24.04.1"

# Check if npm is installed
if ! command -v npm &>/dev/null; then
	log "npm is not installed. Installing..."
	sudo apt-get update
	sudo apt-get install -y nodejs npm
fi

# Check if Balena CLI is installed
if ! command -v balena &>/dev/null; then
	log "Balena CLI is not installed. Installing..."
	sudo npm install -g balena-cli
fi

sudo -v

log "Script started at $(date)"
read -p "Enter Ubuntu version (default: ${DEFAULT_VERSION}): " VERSION_INPUT
UBUNTU_VERSION=${VERSION_INPUT:-$DEFAULT_VERSION}

ISO_NAME="ubuntu-${UBUNTU_VERSION}-desktop-amd64.iso"
ISO_URL="https://releases.ubuntu.com/${UBUNTU_VERSION}/${ISO_NAME}"

function list_potential_usb_drives() {
	log "Listing potential USB drives..."
	# List only removable drives, excluding loop devices, snaps, and system partitions
	lsblk -d -o NAME,SIZE,TYPE,RM,MOUNTPOINT | awk '$3=="disk" && $4=="1" {print}'
}

function download_ubuntu() {
	local download_dir="$1"

	log "Starting download of Ubuntu ${UBUNTU_VERSION} LTS..."
	log "Download URL: ${ISO_URL}"
	log "Download directory: ${download_dir}"

	# Create download directory if it doesn't exist
	mkdir -p "${download_dir}"

	# Check if file already exists
	if [[ -f "${download_dir}/${ISO_NAME}" ]]; then
		log "ISO file already exists. Checking if complete..."
		local existing_size=$(stat -c%s "${download_dir}/${ISO_NAME}")
		log "Existing file size: ${existing_size} bytes"
	fi

	if ! wget -c "${ISO_URL}" -P "${download_dir}"; then
		log "Download failed. Trying alternative URL..."
		local alt_url="https://old-releases.ubuntu.com/releases/${UBUNTU_VERSION}/${ISO_NAME}"
		log "New URL: ${alt_url}"
		if ! wget -c "${alt_url}" -P "${download_dir}"; then
			log "Download failed from both sources."
			return 1
		fi
	fi

	if [[ ! -f "${download_dir}/${ISO_NAME}" ]]; then
		log "Download appears to have failed - ISO file not found"
		return 1
	fi

	log "Download complete: ${download_dir}/${ISO_NAME}"
	log "SHA256 hash of downloaded file:"
	sha256sum "${download_dir}/${ISO_NAME}"
	return 0
}

function flash_usb() {
	local iso_path="$1"
	local usb_device="$2"

	# Verify ISO file exists
	if [[ ! -f "${iso_path}" ]]; then
		log "Error: ISO file ${iso_path} not found!"
		return 1
	fi

	log "WARNING: This will erase all data on ${usb_device}"
	log "Please verify this is the correct device!"
	list_potential_usb_drives
	read -p "Continue? (y/N): " confirm

	if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
		log "Operation cancelled by user"
		return 1
	fi

	log "Starting USB flash process to ${usb_device}..."
	log "Using ISO file: ${iso_path}"

	# Unmount any partitions of the target device
	log "Unmounting any existing partitions..."
	mount | grep "${usb_device}" | cut -d' ' -f1 | while read partition; do
		sudo umount "${partition}" || log "No mounted partition found on ${partition}"
	done

	log "Flashing Ubuntu using Balena CLI..."
	if ! sudo balena local flash "${iso_path}" --drive "${usb_device}" --yes; then
		log "Flashing failed"
		return 1
	fi

	log "USB flash complete!"
	return 0
}

# Main script
log "Starting Ubuntu USB creation script..."

DOWNLOAD_DIR="/tmp/ubuntu_download"
log "Using download directory: ${DOWNLOAD_DIR}"

log "Available USB devices:"
list_potential_usb_drives

# Keep asking for device path until a valid one is provided
while true; do
	read -p "Enter USB device path (e.g., sdb): " USB_DEVICE

	if [[ ! -b "/dev/${USB_DEVICE}" ]]; then
		log "Error: ${USB_DEVICE} is not a valid block device"
		log "Available devices:"
		list_potential_usb_drives
	else
		USB_DEVICE="/dev/${USB_DEVICE}"
		break
	fi
done

log "Selected device: ${USB_DEVICE}"

# Download Ubuntu
if ! download_ubuntu "${DOWNLOAD_DIR}"; then
	log "Download failed, exiting."
	read -p "Press Enter to exit..."
	exit 1
fi

# Flash USB
if ! flash_usb "${DOWNLOAD_DIR}/${ISO_NAME}" "${USB_DEVICE}"; then
	log "Flashing failed, exiting."
	read -p "Press Enter to exit..."
	exit 1
fi

log "Script completed successfully at $(date)"
read -p "Press Enter to exit..."
