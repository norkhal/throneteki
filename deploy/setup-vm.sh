#!/bin/bash
set -euo pipefail

# Throneteki GCP VM Setup Script
# Installs Docker, git, and clones the repo on a Debian/Ubuntu GCP VM.
#
# Usage (run on the GCP VM via SSH):
#   curl -fsSL <raw-url> | sudo bash
#   -- or --
#   sudo bash deploy/setup-vm.sh
#
# After this script completes, run:
#   cd ~/throneteki && CERTBOT_EMAIL=you@example.com bash deploy/init.sh

REPO_URL="https://github.com/norkhal/throneteki.git"
BRANCH="claude/setup-throneteki-gcp-wJQEd"
INSTALL_DIR="/home/${SUDO_USER:-$USER}/throneteki"
ACTUAL_USER="${SUDO_USER:-$USER}"

echo "=== Throneteki GCP VM Setup ==="
echo ""

# Must run as root / with sudo
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run with sudo."
    echo "Usage: sudo bash deploy/setup-vm.sh"
    exit 1
fi

# --- Step 1: Update apt ---
echo "[1/5] Updating package index..."
apt-get update -qq

# --- Step 2: Install prerequisites ---
echo "[2/5] Installing prerequisites (ca-certificates, curl, gnupg, git, openssl)..."
apt-get install -y -qq ca-certificates curl gnupg git openssl > /dev/null

# --- Step 3: Install Docker Engine + Compose plugin ---
echo "[3/5] Installing Docker Engine..."

if command -v docker &> /dev/null && docker compose version &> /dev/null; then
    echo "Docker is already installed, skipping."
else
    # Add Docker's official GPG key
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/$(. /etc/os-release && echo "$ID")/gpg \
        -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    # Add Docker's apt repository
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
        https://download.docker.com/linux/$(. /etc/os-release && echo "$ID") \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
        > /etc/apt/sources.list.d/docker.list

    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin > /dev/null

    # Enable and start Docker
    systemctl enable docker
    systemctl start docker

    echo "Docker installed successfully."
fi

# Add user to docker group so they don't need sudo for docker commands
if ! groups "$ACTUAL_USER" | grep -q docker; then
    usermod -aG docker "$ACTUAL_USER"
    echo "Added $ACTUAL_USER to docker group (takes effect on next login)."
fi

# --- Step 4: Clone the repo ---
echo "[4/5] Cloning throneteki repository..."

if [ -d "$INSTALL_DIR" ]; then
    echo "Directory $INSTALL_DIR already exists."
    echo "Pulling latest changes..."
    cd "$INSTALL_DIR"
    sudo -u "$ACTUAL_USER" git fetch origin "$BRANCH"
    sudo -u "$ACTUAL_USER" git checkout "$BRANCH"
    sudo -u "$ACTUAL_USER" git pull origin "$BRANCH"
else
    sudo -u "$ACTUAL_USER" git clone -b "$BRANCH" "$REPO_URL" "$INSTALL_DIR"
fi

# --- Step 5: Verify ---
echo "[5/5] Verifying installation..."
echo "  Docker:  $(docker --version)"
echo "  Compose: $(docker compose version)"
echo "  Git:     $(git --version)"
echo "  Repo:    $INSTALL_DIR (branch: $BRANCH)"

echo ""
echo "=== VM Setup Complete ==="
echo ""
echo "Next steps:"
echo "  1. Log out and back in (so docker group takes effect), or run: newgrp docker"
echo "  2. Run the deployment init script:"
echo ""
echo "     cd $INSTALL_DIR"
echo "     CERTBOT_EMAIL=you@example.com bash deploy/init.sh"
echo ""
echo "  This will build images, obtain SSL certs, import card data, and start all services."
echo "  The site will be live at https://play.dragonstoneforge.com once complete."
