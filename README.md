# Secure VPS Setup Guide

This project contains a comprehensive shell script (`setup.sh`) to automate the initial setup and security hardening of a fresh Linux VPS (Ubuntu/Debian).

## What the Script Does

1. **System Updates**: Updates package lists and upgrades existing packages.
2. **User Creation**: Creates a new, secure non-root user with `sudo` administrative privileges.
3. **SSH Key Migration**: Automatically copies the root user's authorized SSH keys to the new user, ensuring you use the same secure key to log in.
4. **SSH Hardening**:
   - Disables SSH login for the `root` user (`PermitRootLogin no`).
   - Disables SSH password authentication (`PasswordAuthentication no`), enforcing key-only authentication.
   - Disables keyboard-interactive authentication.
5. **Intrusion Protection**:
   - Installs and configures `fail2ban` to automatically ban IPs showing suspicious brute-force SSH behaviors.
6. **Hostname Configuration**: Updates the VPS hostname and `/etc/hosts` to use a domain name of your choice.
7. **Connection Guide Output**: Provides copy-pasteable client-side configuration blocks for your local `~/.ssh/config`.

---

## Step-by-Step Instructions

### Step 1: Point Your Domain's DNS (Optional but Recommended)
To log in using a domain name like `ssh -i ./pky user@this.vps.host`:
1. Log in to your domain registrar or DNS hosting provider (e.g., Cloudflare, Namecheap, GoDaddy).
2. Create or update an **A Record**:
   - **Host/Name**: `@` (for main domain) or a subdomain (e.g., `vps`, `this.vps.host`).
   - **Value/IP**: The public IP address of your VPS.
   - **TTL**: Auto or 3600 (1 hour).

### Step 2: Upload the Script to Your VPS
From your **local machine**, run `scp` to copy the setup script to the root directory of your VPS:

```bash
# Replace <vps-ip> with your actual VPS IP address
# Replace /path/to/private_key with the path to the SSH private key you use to log in as root
scp -i /path/to/private_key ./setup.sh root@<vps-ip>:/root/setup.sh
```

*Alternative (if you don't want to copy via SCP)*:
SSH into your VPS as root and download it directly or copy-paste the contents:
```bash
ssh root@<vps-ip>
nano setup.sh # paste the script contents, save and exit
```

### Step 3: Run the Script on Your VPS
1. SSH into the VPS as root:
   ```bash
   ssh root@<vps-ip>
   ```
2. Make the script executable and run it:
   ```bash
   chmod +x /root/setup.sh
   /root/setup.sh
   ```
3. Follow the interactive prompts:
   - **Username**: Choose the new username (default is `vpsadmin`).
   - **Password Option**: Choose whether to auto-generate a secure 20-character password (highly recommended) or enter a custom one.
   - **Domain**: Enter your domain name (e.g., `this.vps.host`) if you set one up in Step 1. Leave blank if you only want to use the IP address.

### Step 4: Keep the Root Session Open & Verify!
> [!IMPORTANT]
> **CRITICAL**: Do **NOT** close your active root SSH session. If there was a misconfiguration, closing this session will lock you out permanently.

1. Open a **new terminal window** on your local machine.
2. Test connecting to your new user using the new configuration.

**To connect via Domain Name:**
```bash
ssh -i /path/to/private_key user@this.vps.host
```

**To connect via IP Address:**
```bash
ssh -i /path/to/private_key user@<vps-ip>
```

3. Once connected as the new user, verify you have administrative (sudo) privileges by running:
   ```bash
   sudo -i
   ```
   *(Enter the password that was displayed at the end of the setup script when prompted)*
4. If you can successfully log in and access root using `sudo -i`, you are safe! You can now close both terminal windows.

---

## Setting Up Quick Local SSH Access

To avoid typing the long SSH commands every time, you can add a shortcut configuration to your local machine.

1. On your **local machine**, open or create the SSH config file:
   ```bash
   nano ~/.ssh/config
   ```
2. Add the following block (replace placeholder values):
   ```ssh
   Host my-vps
       HostName this.vps.host   # or use the VPS IP address
       User vpsadmin            # the username you created
       IdentityFile ~/.ssh/id_rsa  # path to your private key on local machine
   ```
3. Save and close the file.
4. Now you can connect to your VPS simply by running:
   ```bash
   ssh my-vps
   ```
