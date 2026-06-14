<h1 align="center">🛡️ Secure VPS Setup</h1>

<p align="center">
  <strong>Automated initialization and security hardening for fresh Linux VPS instances.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/OS-Ubuntu%20%7C%20Debian-blue?style=flat-square&logo=linux" alt="Supported OS">
  <img src="https://img.shields.io/badge/Shell-Bash-green?style=flat-square&logo=gnu-bash" alt="Shell">
</p>

---

## ✨ Features

This script provides a production-ready baseline for any new server by automating the following:

- 📦 **System Updates**: Automatically updates and upgrades system packages.
- 👤 **Secure User Creation**: Generates a cryptographically secure 20-character password and provisions a non-root user with `sudo` access.
- 🔑 **Seamless SSH Key Migration**: Copies your `root` SSH authorized keys directly to the new user.
- 🔒 **SSH Hardening**: Disables `root` SSH logins, disables password-based authentication, and enforces key-only access to prevent brute-force attacks.
- 🛡️ **Intrusion Protection**: Configures `fail2ban` to automatically jail IPs exhibiting malicious SSH brute-force behavior.
- 🌐 **Domain & Hostname Config**: Automatically binds your chosen domain name to the VPS hostname.

---

## 🚀 Quick Start

### 1. Execute on your VPS

Run the following command as `root` on your fresh VPS. You can download and run it directly:

```bash
# SSH into your server as root
ssh root@<vps-ip>

# Download and execute
curl -sO https://raw.githubusercontent.com/takashi728/vps-secure-setup/main/setup.sh
chmod +x setup.sh
./setup.sh
```

### 2. Follow the Prompts
The interactive script will ask you to:
1. Provide a **username** (defaults to `vpsadmin`).
2. Auto-generate a **secure password** or enter your own.
3. Provide a **domain name** (optional).

### 3. Verify Connection (CRITICAL ⚠️)

> **IMPORTANT:** Do **NOT** close your active root SSH session immediately! If there is a configuration error, closing the session may lock you out of your server permanently.

Open a **new terminal window** on your local machine and verify you can connect as the new user:

```bash
# Connect via IP
ssh -i /path/to/private_key new_username@<vps-ip>

# OR Connect via Domain (if DNS is configured)
ssh -i /path/to/private_key new_username@yourdomain.com
```

Once logged in, verify `sudo` access:
```bash
sudo -i
```
*(Enter the password provided by the script).* Once successful, it is safe to close your original root session.

---

## 💻 Local SSH Configuration (Bonus)

To avoid typing long SSH commands every time, you can add a shortcut to your local machine's SSH config.

Add this block to your `~/.ssh/config` file:

```ssh
Host my-vps
    HostName <vps-ip-or-domain>
    User <new_username>
    IdentityFile ~/.ssh/id_rsa  # Update with your actual private key path
```

Now you can connect simply by typing:
```bash
ssh my-vps
```

---

<p align="center">
  <i>Built with security and simplicity in mind.</i>
</p>
