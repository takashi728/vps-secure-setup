<h1 align="center">🛡️ Secure VPS Setup</h1>

<p align="center">
  <strong>Minimal, focused hardening script for a fresh Linux VPS — no bloat, no surprises.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/OS-Ubuntu%20%7C%20Debian-blue?style=flat-square&logo=linux" alt="Supported OS">
  <img src="https://img.shields.io/badge/Shell-Bash-green?style=flat-square&logo=gnu-bash" alt="Shell">
</p>

---

## 🎯 Scope

This script covers **one job**: bootstrap a secure non-root user on a fresh VPS and lock down SSH. Firewall configuration (UFW / firewalld) is intentionally out of scope and handled separately.

**What it does:**
- Creates a non-root sudo user with a randomly generated, cryptographically secure 20-character password.
- Copies `root`'s `authorized_keys` to the new user so the **same SSH key** continues to work.
- Hardens SSH: disables root login and all password-based authentication.
- Installs and enables `fail2ban` with its default configuration.

**What it does NOT do:**
- Configure a firewall (handle this yourself with UFW or firewalld after setup).
- Set up a hostname or domain name.
- Modify swap, cron jobs, or unattended upgrades.

---

## 🚀 Workflow

### Step 1 — First login & full system update

SSH in as root using your key, update everything including the kernel, then reboot:

```bash
ssh -i /path/to/private_key root@<vps-ip>
```

```bash
apt-get update && apt-get dist-upgrade -y && reboot
```

### Step 2 — SSH back in as root

```bash
ssh -i /path/to/private_key root@<vps-ip>
```

### Step 3 — Download and run the setup script

```bash
curl -sO https://raw.githubusercontent.com/takashi728/vps-secure-setup/main/setup.sh
chmod +x setup.sh
./setup.sh
```

The script will prompt for a username (default: `vpsadmin`) and take care of the rest.

---

## ✅ After the Script

> **⚠️ Do NOT close your active root session until you verify the new user works.**

Open a **new terminal** and test the new user:

```bash
# Same key as root, new username
ssh -i /path/to/private_key <new_username>@<vps-ip>
```

Verify sudo access:

```bash
sudo -i
```

The generated password is saved to `/root/.vps-setup-credentials` (root-readable only). Retrieve it with:

```bash
cat /root/.vps-setup-credentials
```

Once access is confirmed, it is safe to close the root session.

---

## 💻 Optional: Local SSH Config Shortcut

Add this to your local `~/.ssh/config` for quick access:

```ssh
Host my-vps
    HostName <vps-ip>
    User <new_username>
    IdentityFile ~/.ssh/id_ed25519
```

Then connect simply with:

```bash
ssh my-vps
```

---

## 🔒 Next Steps (Manual)

After verifying your new user session, consider:

1. **Firewall** — Configure UFW or firewalld to restrict open ports.
2. **Unattended upgrades** — `apt-get install unattended-upgrades`
3. **SSH port change** — Optionally move SSH off port 22 in `/etc/ssh/sshd_config`.

---

<p align="center"><i>Built with security and simplicity in mind.</i></p>
