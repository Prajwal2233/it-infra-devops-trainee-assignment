#!/bin/bash
#############################################################################
# setup_server.sh
#
# Task 1: System Provisioning & Linux Administration
#
# What this does:
#   1. Updates the system
#   2. Creates a 'trainee' user with sudo privileges
#   3. Installs an SSH public key for 'trainee'
#   4. Hardens sshd_config (no root login, key-only auth, port 2222)
#   5. Configures UFW to allow only SSH(2222), HTTP(80), HTTPS(443)
#
# Run as root on a FRESH Ubuntu server:
#   sudo ./setup_server.sh
#
# !!! IMPORTANT - AVOID LOCKOUT !!!
# Do NOT close your current session until you have opened a SECOND
# terminal and confirmed you can log in as:
#   ssh -p 2222 trainee@<server-ip>
# using the key you provide below. If you get locked out, you will
# need console/VNC access (e.g. cloud provider's web console) to fix it.
#############################################################################

set -euo pipefail

SSH_PORT=2222
NEW_USER="trainee"
SSHD_CONFIG="/etc/ssh/sshd_config"

if [ "$EUID" -ne 0 ]; then
    echo "Please run this script as root (sudo ./setup_server.sh)"
    exit 1
fi

echo "===== Step 1/6: Updating system packages ====="
apt update && apt upgrade -y

echo "===== Step 2/6: Creating '${NEW_USER}' user with sudo privileges ====="
if id "$NEW_USER" &>/dev/null; then
    echo "User '${NEW_USER}' already exists — skipping creation."
else
    adduser --gecos "" "$NEW_USER"
    usermod -aG sudo "$NEW_USER"
    echo "User '${NEW_USER}' created and added to the 'sudo' group."
fi

echo "===== Step 3/6: Installing SSH public key for '${NEW_USER}' ====="
USER_HOME="/home/${NEW_USER}"
mkdir -p "${USER_HOME}/.ssh"
touch "${USER_HOME}/.ssh/authorized_keys"

echo "Paste the PUBLIC key for ${NEW_USER} (e.g. contents of ~/.ssh/id_ed25519.pub)"
echo "then press ENTER:"
read -r PUB_KEY

if [ -z "$PUB_KEY" ]; then
    echo "No key provided. Add it manually later to ${USER_HOME}/.ssh/authorized_keys"
else
    echo "${PUB_KEY}" >> "${USER_HOME}/.ssh/authorized_keys"
fi

chmod 700 "${USER_HOME}/.ssh"
chmod 600 "${USER_HOME}/.ssh/authorized_keys"
chown -R "${NEW_USER}:${NEW_USER}" "${USER_HOME}/.ssh"
echo "SSH key installed for ${NEW_USER}."

echo "===== Step 4/6: Hardening sshd_config ====="
cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak.$(date +%s)"

sed -i "s/^#\?Port .*/Port ${SSH_PORT}/" "$SSHD_CONFIG"
sed -i "s/^#\?PermitRootLogin .*/PermitRootLogin no/" "$SSHD_CONFIG"
sed -i "s/^#\?PasswordAuthentication .*/PasswordAuthentication no/" "$SSHD_CONFIG"
sed -i "s/^#\?PubkeyAuthentication .*/PubkeyAuthentication yes/" "$SSHD_CONFIG"

grep -q "^Port ${SSH_PORT}" "$SSHD_CONFIG" || echo "Port ${SSH_PORT}" >> "$SSHD_CONFIG"

echo "Backed up original config. New settings applied:"
grep -E "^Port|^PermitRootLogin|^PasswordAuthentication|^PubkeyAuthentication" "$SSHD_CONFIG"

echo "===== Step 5/6: Configuring UFW firewall ====="
apt install -y ufw
ufw default deny incoming
ufw default allow outgoing
ufw allow ${SSH_PORT}/tcp comment 'SSH (custom port)'
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'
ufw --force enable

echo "===== Step 6/6: Restarting SSH service ====="
systemctl restart sshd

echo ""
echo "================================================================"
echo " SETUP COMPLETE"
echo " New login command : ssh -p ${SSH_PORT} ${NEW_USER}@<server-ip>"
echo " VERIFY THIS WORKS IN A NEW TERMINAL BEFORE CLOSING THIS SESSION"
echo "================================================================"
ufw status verbose
