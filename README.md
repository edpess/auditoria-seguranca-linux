[![English](https://img.shields.io/badge/English-blue)](README.md)
[![Portuguese](https://img.shields.io/badge/PT-red)](README.pt.md)

# 🔒 Security Audit and Hardening

A professional and robust Bash script for auditing and hardening the security of Linux servers (Debian/Ubuntu). It performs critical security checks and applies hardening fixes interactively or automatically.

## ✨ Features

The script performs 11 steps to check and harden the system:

1.  **🔍 Pending Updates**: Checks for and applies operating system security updates.
2.  **🔌 Ports and Services**: Lists open ports and listening services (using `ss` or `netstat`).
3.  **🛡️ Firewall (UFW)**: Checks if UFW is active, configures restrictive policies, and allows interactive review of rules.
4.  **🔒 AppArmor**: Ensures that the Mandatory Access Control (MAC) process isolation system is active.
5.  **🔑 SSH Hardening**: Blocks root logins, tests the configuration before restarting the service, and creates an automatic backup.
6.  **⛔ Brute-Force Protection (Fail2Ban)**: Installs and configures Fail2Ban to protect SSH (blocks IP addresses after 3 attempts).
7.  **📜 Failed Login Attempts**: Displays the most recent invalid password attempts on SSH.
8.  **✅ System Integrity**: Uses `debsums` to verify the integrity of binaries and libraries, with a progress bar.
9.  **🦠 Antivirus (ClamAV)**: Checks the ClamAV installation, updates the definition files, and schedules scans.
10. **🎯 Rootkit Hunter**: Detects the presence of tools such as `rkhunter` and `chkrootkit` and their scheduled tasks.
11. **🌐 Outbound Connections**: Maps all established external connections, identifying processes and destination ports.

At the end, a consolidated report is displayed showing the status of each defense layer and a final conclusion regarding the system’s security posture.

## ⚙️ Execution Modes

The script offers two main modes:

- **Interactive Mode (Default)**: Prompts the user (`y/n`) for each corrective action. Allows full control over what will be changed on the system.
- **Automatic Mode (`--auto` or `-y`)**: Requires no user interaction. Automatically applies standard security best practices (enables the firewall, installs and configures Fail2Ban, blocks SSH root access, enables AppArmor, etc.). Ideal for initial setups or automation via provisioning scripts (cloud-init, Ansible, etc.).

## 📋 Prerequisites

- **Debian** or **Ubuntu** operating system (or derivatives that use `apt`).
- **Bash** (standard on all Linux systems).
- **Root** privileges (sudo).

## 🚀 How to Use

### 1. Download and Permissions

Clone the repository or download the script, and grant it execute permissions:

```bash
wget https://raw.githubusercontent.com/seu-usuario/seu-repo/main/auditoria_hardening.sh
# or
curl -O https://raw.githubusercontent.com/seu-usuario/seu-repo/main/auditoria_hardening.sh

chmod +x auditoria_hardening.sh
```
### 2. Execution

> **⚠️ Important:** Always run the script as superuser.

**A. Interactive Mode (default):**

```bash
sudo bash hardening_audit.sh
```

You will be guided step by step and can decide on each corrective action.

**B. Automatic Mode (non-interactive):**

```bash
sudo bash hardening_audit.sh --auto
# or
sudo bash hardening_audit.sh -y
```

The script will apply all security configurations automatically. See the “Behavior in Automatic Mode” section below.

## 🤖 Behavior in Automatic Mode (`--auto`)

When run with `--auto`, the script makes the following decisions:

| Action/Configuration                       | Automatic Decision           |
|-----------------------------------------|------------------------------|
| Update system packages            | **No** (checks only)    |
| Enable Firewall (UFW)                   | **Yes** (ports 80, 443, 22) |
| Enable AppArmor                         | **Yes**                      |
| Block root login via SSH              | **Yes**                      |
| Install and configure Fail2Ban          | **Yes**                      |
| Check integrity with `debsums`     | **Yes** (full)           |
| Enable automatic ClamAV updates     | **Yes**                      |
| Schedule chkrootkit                      | **Yes** (daily at 3:00 AM)    |

**This is safe for an initial setup, but in environments with complex firewall rules, interactive mode is recommended for careful review.**

## 🧠 Code Structure

- **Initial Validation**: Ensures execution as Bash with root privileges.
- **Helper Functions**: `ask_yes_no` and `ask_input` standardize interaction and support automatic mode.
- **Modular Checks**: Each step (updates, firewall, SSH, etc.) is an independent block.
- **Consolidated Report**: Variables store the status of each step for the final summary.
- **Cleanup**: Temporary files are created with `mktemp` and removed at the end.

## 📝 Sample Output (Final Report)

```text
==============================================
          FINAL AUDIT REPORT
==============================================
• OS Updates  : OK (Updated)
• Ports and Services   : Analyzed (ss)
• Firewall            : OK (Active and Reviewed)
• AppArmor (MAC)      : OK (Active)
• SSH Hardening       : OK (Root blocked)
• Fail2Ban (Blocking) : OK (Active)
• System Integrity    : OK (Integrity intact)
• Antivirus           : Installed and Updating | Active Scan (Via global rule)
• Rootkit Hunter      : rkhunter: Active (Logged) | chkrootkit: Active (Logged)
----------------------------------------------
       OUTBOUND CONNECTIONS ESTABLISHED
----------------------------------------------
Destination Port: 443 | Program: curl | Location: /usr/bin/curl
Destination Port: 53  | Program: systemd-resolve | Location: /usr/lib/systemd/systemd-resolved
----------------------------------------------
FINAL CONCLUSION: Excellent! Your system has its key defense layers active.
==============================================
```

## 💡 Post-Execution Recommendations

- **Review the firewall rules**: Run `sudo ufw status` to check which ports are open.
- **Test SSH access**: If you’ve blocked root access, make sure you have a regular user with `sudo` privileges configured before logging out.
- **Monitor the logs**: Check `/var/log/auth.log` and `fail2ban-client status` to verify active blocks.
- **Run periodically**: Add the script to cron (use `--auto` mode for checks only) or run it manually after system changes.

---

## 🔗 Contribute

Feel free to open **Issues** for bugs or suggestions, or submit **Pull Requests**. Any help is welcome to make this script even more robust!

**License**: MIT
