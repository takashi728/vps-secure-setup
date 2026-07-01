#!/usr/bin/env bash

# ==============================================================================
# Secure VPS Setup Script
# Tested on Debian, Ubuntu, and derivatives.
# Must be executed as root.
#
# Workflow assumption:
#   1. SSH into VPS as root using your SSH key.
#   2. Run: apt-get update && apt-get dist-upgrade -y && reboot
#   3. SSH back in as root, then run this script.
#
# What this script does:
#   - Creates a non-root sudo user with a cryptographically secure password.
#   - Copies root's authorized_keys to the new user (same SSH key works).
#   - Hardens SSH: disables root login and password authentication.
#   - Installs and enables fail2ban with its default configuration.
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# Color helpers
# ------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC}    $1"; }
log_success() { echo -e "${GREEN}[OK]${NC}      $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC}    $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC}   $1"; }

# ------------------------------------------------------------------------------
# Root check
# ------------------------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root."
    exit 1
fi

# ------------------------------------------------------------------------------
# Detect VPS public IP
# ------------------------------------------------------------------------------
VPS_IP=$(curl -s --max-time 5 https://icanhazip.com 2>/dev/null \
      || curl -s --max-time 5 https://api.ipify.org 2>/dev/null \
      || true)

if [[ -z "$VPS_IP" ]]; then
    log_warning "Could not detect public IP. You will need to fill it in manually."
    VPS_IP="<YOUR_VPS_IP>"
fi

echo
log_info "Starting Secure VPS Setup..."
echo "--------------------------------------------------"

# ------------------------------------------------------------------------------
# 1. Gather username
# ------------------------------------------------------------------------------
default_user="vpsadmin"
read -rp "Enter new sudo username [default: ${default_user}]: " username
username=${username:-$default_user}

if [[ ! "$username" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
    log_error "Invalid username. Must start with a lowercase letter or underscore."
    exit 1
fi

echo "--------------------------------------------------"

# ------------------------------------------------------------------------------
# 2. System packages
# ------------------------------------------------------------------------------
log_info "Installing required packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends sudo fail2ban curl openssh-server
log_success "Packages installed."

# ------------------------------------------------------------------------------
# 3. Create user and assign sudo
# ------------------------------------------------------------------------------
log_info "Setting up user '${username}'..."

if id "$username" &>/dev/null; then
    log_warning "User '${username}' already exists. Updating password and sudo group."
else
    useradd -m -s /bin/bash "$username"
    log_success "User '${username}' created."
fi

# Generate a cryptographically secure 20-character alphanumeric password
password=$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 20)
if [[ ${#password} -lt 20 ]]; then
    log_error "Password generation failed."
    exit 1
fi

# Set password securely (avoids exposing it in process list)
chpasswd <<< "${username}:${password}"
log_success "Secure password set for '${username}'."

# Add to sudo group
if getent group sudo &>/dev/null; then
    usermod -aG sudo "$username"
elif getent group wheel &>/dev/null; then
    usermod -aG wheel "$username"
else
    groupadd sudo
    usermod -aG sudo "$username"
fi
log_success "'${username}' added to sudo group."

# ------------------------------------------------------------------------------
# 4. Copy root SSH authorized_keys to new user
# ------------------------------------------------------------------------------
log_info "Migrating root SSH keys to '${username}'..."

user_home=$(eval echo "~${username}")
user_ssh_dir="${user_home}/.ssh"
root_auth_keys="/root/.ssh/authorized_keys"

mkdir -p "$user_ssh_dir"

if [[ -f "$root_auth_keys" ]]; then
    cp "$root_auth_keys" "${user_ssh_dir}/authorized_keys"
    log_success "Root authorized_keys copied to '${username}'."
else
    log_warning "No authorized_keys found at ${root_auth_keys}."
    read -rp "Paste a public SSH key for '${username}' (leave empty to skip): " pub_key
    if [[ -n "$pub_key" ]]; then
        echo "$pub_key" > "${user_ssh_dir}/authorized_keys"
        log_success "Public key written."
    else
        log_warning "No SSH key added. You must add one manually before locking down SSH."
    fi
fi

chmod 700 "$user_ssh_dir"
[[ -f "${user_ssh_dir}/authorized_keys" ]] && chmod 600 "${user_ssh_dir}/authorized_keys"
chown -R "${username}:${username}" "$user_ssh_dir"
log_success "SSH directory permissions set for '${username}'."

# ------------------------------------------------------------------------------
# 5. Harden SSH configuration
# ------------------------------------------------------------------------------
log_info "Hardening SSH configuration..."

SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_CONFIG_BAK="${SSHD_CONFIG}.bak.$(date +%F_%T)"
cp "$SSHD_CONFIG" "$SSHD_CONFIG_BAK"
log_info "Backup created at ${SSHD_CONFIG_BAK}"

# Use a drop-in override file to avoid fighting with cloud-init defaults.
# This takes precedence because it is named 00-secure.conf.
DROPIN_DIR="/etc/ssh/sshd_config.d"
DROPIN_FILE="${DROPIN_DIR}/00-secure.conf"

if [[ -d "$DROPIN_DIR" ]]; then
    # Write a clean drop-in file (overwrite any stale version)
    cat > "$DROPIN_FILE" <<'EOF'
# Managed by vps-secure-setup — do not edit manually.
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no
EOF
    log_success "SSH drop-in config written to ${DROPIN_FILE}."
else
    # No drop-in support; patch sshd_config directly
    patch_sshd() {
        local key="$1" value="$2"
        if grep -qE "^#?\s*${key}\s+" "$SSHD_CONFIG"; then
            sed -i -E "s|^#?\s*${key}\s+.*|${key} ${value}|" "$SSHD_CONFIG"
        else
            echo "${key} ${value}" >> "$SSHD_CONFIG"
        fi
    }
    patch_sshd "PermitRootLogin"              "no"
    patch_sshd "PasswordAuthentication"       "no"
    patch_sshd "PubkeyAuthentication"         "yes"
    patch_sshd "ChallengeResponseAuthentication" "no"
    patch_sshd "KbdInteractiveAuthentication" "no"
    log_success "SSH settings patched directly in ${SSHD_CONFIG}."
fi

# Validate and reload SSH
if sshd -t; then
    log_success "SSH configuration is valid."
    if systemctl is-active --quiet ssh 2>/dev/null; then
        systemctl reload ssh
    elif systemctl is-active --quiet sshd 2>/dev/null; then
        systemctl reload sshd
    else
        service ssh reload 2>/dev/null || service sshd reload
    fi
    log_success "SSH service reloaded."
else
    log_error "SSH config validation failed! Restoring backup."
    cp "$SSHD_CONFIG_BAK" "$SSHD_CONFIG"
    [[ -f "$DROPIN_FILE" ]] && rm -f "$DROPIN_FILE"
    exit 1
fi

# ------------------------------------------------------------------------------
# 6. Enable fail2ban with default configuration
# ------------------------------------------------------------------------------
log_info "Enabling fail2ban..."
systemctl enable fail2ban
systemctl restart fail2ban
log_success "fail2ban enabled and started (default config)."

# ------------------------------------------------------------------------------
# 7. Save credentials to a root-only file
# ------------------------------------------------------------------------------
CREDS_FILE="/root/.vps-setup-credentials"
cat > "$CREDS_FILE" <<EOF
# Generated by vps-secure-setup on $(date)
username = ${username}
password = ${password}
vps_ip   = ${VPS_IP}
EOF
chmod 600 "$CREDS_FILE"

# ------------------------------------------------------------------------------
# 8. Done — print connection guide
# ------------------------------------------------------------------------------
echo
echo "--------------------------------------------------"
log_success "Secure VPS setup complete!"
echo "--------------------------------------------------"
echo -e "${YELLOW}Credentials saved to: ${GREEN}${CREDS_FILE}${NC} (root-readable only)"
echo -e "Username : ${GREEN}${username}${NC}"
echo -e "VPS IP   : ${GREEN}${VPS_IP}${NC}"
echo
echo -e "${BLUE}=== How to connect ===${NC}"
echo -e "  ${GREEN}ssh -i /path/to/private_key ${username}@${VPS_IP}${NC}"
echo
echo -e "Or add to your local ${YELLOW}~/.ssh/config${NC}:"
cat <<EOF
Host my-vps
    HostName ${VPS_IP}
    User ${username}
    IdentityFile ~/.ssh/id_ed25519
EOF
echo
echo -e "${RED}⚠  WARNING:${NC} ${YELLOW}Do NOT close this root session yet!${NC}"
echo    "  1. Open a new terminal and test: ssh -i /path/to/key ${username}@${VPS_IP}"
echo    "  2. Verify sudo works: sudo -i"
echo    "  3. Only close this session once you have confirmed access."
echo "--------------------------------------------------"
