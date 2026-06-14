#!/usr/bin/env bash

# ==============================================================================
# Secure VPS Setup Script
# Works on Debian, Ubuntu, and derivatives.
# Must be executed as root.
# ==============================================================================

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions for logs
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root. Please run with sudo or as root user."
    exit 1
fi

# Detect system IP
VPS_IP=$(curl -s --max-time 5 https://icanhazip.com || curl -s --max-time 5 https://api.ipify.org || echo "YOUR_VPS_IP")

log_info "Starting Secure VPS Setup..."
echo "--------------------------------------------------"

# ------------------------------------------------------------------------------
# 1. Gather User Inputs
# ------------------------------------------------------------------------------
echo -e "${YELLOW}--- Configuration ---${NC}"

# Username selection
default_user="vpsadmin"
read -rp "Enter new username [default: $default_user]: " username
username=${username:-$default_user}

# Validate username
if [[ ! "$username" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
    log_error "Invalid username. Must start with a lowercase letter or underscore, followed by lowercase letters, numbers, hyphens, or underscores."
    exit 1
fi

# Password configuration
generate_pass="y"
read -rp "Would you like to automatically generate a secure password? (y/n) [default: y]: " generate_pass
generate_pass=${generate_pass:-y}

if [[ "$generate_pass" =~ ^[yY](es)?$ ]]; then
    # Generate a strong 20-character password using openssl or /dev/urandom
    if command -v openssl >/dev/null 2>&1; then
        password=$(openssl rand -base64 24 | tr -d '+/=' | head -c 20)
    else
        password=$(tr -dc 'A-Za-z0-9!@#%^*(-+=' < /dev/urandom | head -c 20)
    fi
else
    # Prompt for password (masked input)
    while true; do
        read -rsp "Enter password for $username: " password
        echo
        read -rsp "Confirm password: " password_confirm
        echo
        if [[ "$password" == "$password_confirm" ]]; then
            if [[ ${#password} -lt 12 ]]; then
                log_warning "Password is short (${#password} chars). A minimum of 12 characters is recommended."
                read -rp "Use it anyway? (y/n): " use_short
                if [[ "$use_short" =~ ^[yY](es)?$ ]]; then
                    break
                fi
            else
                break
            fi
        else
            log_error "Passwords do not match. Try again."
        fi
    done
fi

# Domain / Hostname setup
read -rp "Enter your domain name (e.g., this.vps.host) [leave empty to skip]: " domain_name

echo "--------------------------------------------------"

# ------------------------------------------------------------------------------
# 2. System Update & Dependencies
# ------------------------------------------------------------------------------
log_info "Updating system packages and installing dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get upgrade -y
apt-get install -y sudo fail2ban curl openssh-server

# ------------------------------------------------------------------------------
# 3. Create User & Configure Sudo
# ------------------------------------------------------------------------------
log_info "Creating user '$username'..."

# Create the user if they don't exist
if id "$username" >/dev/null 2>&1; then
    log_warning "User '$username' already exists. Updating password and sudo privileges."
else
    useradd -m -s /bin/bash "$username"
    log_success "User '$username' created."
fi

# Set password
echo "$username:$password" | chpasswd
log_success "Password set for '$username'."

# Add to sudo group
if getent group sudo >/dev/null; then
    usermod -aG sudo "$username"
    log_success "Added '$username' to group 'sudo'."
elif getent group wheel >/dev/null; then
    usermod -aG wheel "$username"
    log_success "Added '$username' to group 'wheel'."
else
    log_warning "Neither 'sudo' nor 'wheel' group found. Creating 'sudo' group."
    groupadd sudo
    usermod -aG sudo "$username"
fi

# ------------------------------------------------------------------------------
# 4. Copy SSH Authorized Keys
# ------------------------------------------------------------------------------
log_info "Migrating SSH keys..."

user_home=$(eval echo "~$username")
user_ssh_dir="$user_home/.ssh"
root_auth_keys="/root/.ssh/authorized_keys"

mkdir -p "$user_ssh_dir"

if [[ -f "$root_auth_keys" ]]; then
    cp "$root_auth_keys" "$user_ssh_dir/authorized_keys"
    log_success "Successfully copied root authorized keys to '$username'."
else
    log_warning "No root SSH keys found at $root_auth_keys."
    read -rp "Would you like to manually paste a public key for '$username'? (y/n) [default: n]: " add_key_manual
    add_key_manual=${add_key_manual:-n}
    if [[ "$add_key_manual" =~ ^[yY](es)?$ ]]; then
        read -rp "Paste your public SSH key (starting with ssh-rsa, ssh-ed25519, etc.): " pub_key
        echo "$pub_key" > "$user_ssh_dir/authorized_keys"
        log_success "Public key written."
    else
        log_warning "Continuing without adding SSH keys. Note: You will need password auth enabled until you add a key!"
    fi
fi

# Set strict permissions
chmod 700 "$user_ssh_dir"
if [[ -f "$user_ssh_dir/authorized_keys" ]]; then
    chmod 600 "$user_ssh_dir/authorized_keys"
fi
chown -R "$username:$username" "$user_ssh_dir"
log_success "Set correct ownership and permissions for '$username/.ssh'."

# ------------------------------------------------------------------------------
# 5. Hostname & Domain Configuration
# ------------------------------------------------------------------------------
if [[ -n "$domain_name" ]]; then
    log_info "Setting hostname to '$domain_name'..."
    
    # Set hostname
    if command -v hostnamectl >/dev/null 2>&1; then
        hostnamectl set-hostname "$domain_name"
    else
        echo "$domain_name" > /etc/hostname
        hostname "$domain_name"
    fi
    
    # Update /etc/hosts
    if ! grep -q "$domain_name" /etc/hosts; then
        echo "127.0.1.1  $domain_name $(echo "$domain_name" | cut -d. -f1)" >> /etc/hosts
    fi
    log_success "Hostname set to '$domain_name'."
fi

# ------------------------------------------------------------------------------
# 6. Secure SSH Configuration
# ------------------------------------------------------------------------------
log_info "Hardening SSH configuration..."

SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_CONFIG_BAK="$SSHD_CONFIG.bak.$(date +%F_%T)"
cp "$SSHD_CONFIG" "$SSHD_CONFIG_BAK"
log_info "Backup of sshd_config created at $SSHD_CONFIG_BAK"

# Replace config values safely or append if they don't exist
update_sshd_config() {
    local key=$1
    local value=$2
    # Update main config
    if grep -qE "^#?\s*$key\s+" "$SSHD_CONFIG"; then
        sed -i -E "s/^#?\s*$key\s+.*/$key $value/" "$SSHD_CONFIG"
    else
        echo "$key $value" >> "$SSHD_CONFIG"
    fi
    
    # Write to 00-secure.conf to override any cloud-init includes that load first
    if [[ -d "/etc/ssh/sshd_config.d" ]]; then
        echo "$key $value" >> /etc/ssh/sshd_config.d/00-secure.conf
    fi
}

# Clear previous secure conf if it exists
if [[ -f "/etc/ssh/sshd_config.d/00-secure.conf" ]]; then
    rm /etc/ssh/sshd_config.d/00-secure.conf
fi

# Apply sshd hardening rules
update_sshd_config "PermitRootLogin" "no"
update_sshd_config "PasswordAuthentication" "no"
update_sshd_config "PubkeyAuthentication" "yes"
update_sshd_config "ChallengeResponseAuthentication" "no"
update_sshd_config "KbdInteractiveAuthentication" "no"

# Validate SSH configuration before restarting
if sshd -t; then
    log_success "SSH configuration is valid."
    # Restart SSH service
    if systemctl is-active ssh >/dev/null 2>&1; then
        systemctl reload ssh
        log_success "SSH service reloaded."
    elif systemctl is-active sshd >/dev/null 2>&1; then
        systemctl reload sshd
        log_success "SSHD service reloaded."
    else
        service ssh reload || service sshd reload
        log_success "SSH service reloaded (fallback service manager)."
    fi
else
    log_error "SSH configuration validation failed! Restoring backup config."
    cp "$SSHD_CONFIG_BAK" "$SSHD_CONFIG"
    exit 1
fi

# ------------------------------------------------------------------------------
# 7. Configure Fail2ban
# ------------------------------------------------------------------------------
log_info "Configuring Fail2ban..."

# Setup Fail2ban jail config for SSH
FAIL2BAN_LOCAL="/etc/fail2ban/jail.local"
if [[ ! -f "$FAIL2BAN_LOCAL" ]]; then
    cat <<EOF > "$FAIL2BAN_LOCAL"
[sshd]
enabled = true
port = ssh
filter = sshd
# Inherits logpath/backend from jail.conf defaults correctly for OS
maxretry = 5
bantime = 1h
findtime = 10m
EOF
    systemctl restart fail2ban || service fail2ban restart
    log_success "Fail2ban SSH protection configured."
fi

# ------------------------------------------------------------------------------
# 8. Setup Complete & Output Credentials
# ------------------------------------------------------------------------------
echo "--------------------------------------------------"
log_success "Secure VPS setup is complete!"
echo "--------------------------------------------------"
echo -e "${YELLOW}Please save these credentials securely:${NC}"
echo -e "Username:  ${GREEN}$username${NC}"
echo -e "Password:  ${GREEN}$password${NC}"
echo -e "VPS IP:    ${GREEN}$VPS_IP${NC}"
if [[ -n "$domain_name" ]]; then
echo -e "Domain:    ${GREEN}$domain_name${NC}"
fi
echo "--------------------------------------------------"

echo -e "${BLUE}=== Local Connection Guide ===${NC}"
echo "To log in from your local machine, use one of the following:"
echo

if [[ -n "$domain_name" ]]; then
    echo -e "Option A: Connect via Domain Name (once DNS A record points to $VPS_IP)"
    echo -e "  ${GREEN}ssh -i /path/to/private_key $username@$domain_name${NC}"
    echo
fi

echo -e "Option B: Connect via IP Address"
echo -e "  ${GREEN}ssh -i /path/to/private_key $username@$VPS_IP${NC}"
echo
echo -e "Option C: Setup local SSH Config for quick access"
echo -e "Add this snippet to your local machine's file ${YELLOW}~/.ssh/config${NC}:"
echo -e "--------------------------------------------------"
cat <<EOF
Host ${domain_name:-my-vps}
    HostName ${domain_name:-$VPS_IP}
    User $username
    IdentityFile ~/.ssh/id_rsa  # <-- Replace with your actual private key path
EOF
echo -e "--------------------------------------------------"
echo -e "Once added, you can connect simply by typing:"
echo -e "  ${GREEN}ssh ${domain_name:-my-vps}${NC}"
echo "--------------------------------------------------"
echo -e "${RED}IMPORTANT WARNING:${NC}"
echo -e "${YELLOW}DO NOT close your current active root session!${NC}"
echo -e "1. Open a new terminal window on your local machine."
echo -e "2. Test connecting to the new user using one of the options above."
echo -e "3. Verify you can run sudo commands (e.g., run '${GREEN}sudo -i${NC}' or '${GREEN}sudo apt update${NC}')."
echo -e "Only close this root session after confirming you can successfully connect and use sudo."
echo "--------------------------------------------------"
