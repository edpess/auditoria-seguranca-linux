#!/bin/bash

# ==============================================================================
# SECURITY AUDIT AND HARDENING (v23 - Professional & Resilient Edition)
# ==============================================================================

# Bash validation (Ensures support for arrays, read -t and advanced formatting)
[ -n "$BASH_VERSION" ] || { echo "Error: This script requires BASH. Run with: sudo bash $0"; exit 1; }

# Ensures root privileges
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo $0)."
  exit 1
fi

# Detects Non-Interactive mode (--auto or -y)
AUTO_MODE=0
if [[ "$1" == "--auto" || "$1" == "-y" ]]; then
    AUTO_MODE=1
    echo "⚠️ AUTOMATIC MODE ACTIVATED: The script will not ask for confirmations and will apply default security rules."
    sleep 2
fi

echo "=============================================="
echo "  SECURITY AUDIT AND HARDENING               "
echo "  Date: $(date '+%Y-%m-%d %H:%M:%S')          "
echo "=============================================="

# Global Variables
REL_ATUALIZACAO="Pending"
REL_PORTAS="Pending"
REL_FIREWALL="Pending"
REL_APPARMOR="Pending"
REL_SSH="Pending"
REL_FAIL2BAN="Pending"
REL_INTEGRIDADE="Pending"
REL_ANTIVIRUS="Pending"
REL_ROOTKIT=""
ALERTA_CRITICO=0
LISTA_CONEXOES=$(mktemp)

# ==============================================================================
# AUXILIARY FUNCTIONS
# ==============================================================================

# Standardized question with loop and automatic mode support
ask_yes_no() {
    local prompt="$1"
    local default_auto="$2" # "y" or "n" for auto mode
    local answer

    if [ "$AUTO_MODE" -eq 1 ]; then
        echo -e "${prompt} \033[1;32m[AUTO: ${default_auto^^}]\033[0m"
        [[ "$default_auto" =~ ^[Yy]$ ]] && return 0 || return 1
    fi

    while true; do
        read -p "$prompt (y/n): " answer
        case "$answer" in
            [Yy]* ) return 0 ;;
            [Nn]* ) return 1 ;;
            * ) echo -e "\033[1;31mPlease answer with 'y' (yes) or 'n' (no).\033[0m" ;;
        esac
    done
}

# Prompt for custom data (e.g., Ports)
ask_input() {
    local prompt="$1"
    local var_name="$2"
    local input

    if [ "$AUTO_MODE" -eq 1 ]; then
        eval "$var_name=\"\""
        return 0
    fi

    read -p "$prompt" input
    eval "$var_name=\"$input\""
}

# Checks if SSH SERVER is installed (ignores the client)
SSH_INSTALLED=0
if [ -x "/usr/sbin/sshd" ] || dpkg-query -W -f='${Status}' openssh-server 2>/dev/null | grep -q "ok installed"; then
    SSH_INSTALLED=1
fi

# ==============================================================================
# START OF CHECKS
# ==============================================================================

echo ""
echo "[1] CHECKING PENDING UPDATES..."
if ! apt-get update -qq; then
    echo "⚠️ Failed to connect to repositories (Network issue or APT lock). The script will continue."
    REL_ATUALIZACAO="Network/APT Failure"
    ALERTA_CRITICO=$((ALERTA_CRITICO + 1))
else
    UPGRADES=$(apt-get -s upgrade 2>/dev/null | grep -P '^\d+ upgraded' | awk '{print $1}')
    if [ -n "$UPGRADES" ] && [ "$UPGRADES" -gt 0 ]; then
        echo "⚠️ WARNING: There are $UPGRADES packages needing updates."
        if ask_yes_no "Do you want to update the system now? (Run 'apt upgrade -y')" "n"; then
            echo "Updating packages... This may take a few minutes."
            if apt-get upgrade -y; then
                echo "✅ System successfully updated."
                REL_ATUALIZACAO="OK (Updated just now)"
            else
                echo "❌ Failed during update."
                REL_ATUALIZACAO="Error during Update"
                ALERTA_CRITICO=$((ALERTA_CRITICO + 1))
            fi
        else
            echo "❌ Update ignored."
            REL_ATUALIZACAO="Outdated ($UPGRADES packages)"
            ALERTA_CRITICO=$((ALERTA_CRITICO + 1))
        fi
    else
        echo "✅ System is already up to date."
        REL_ATUALIZACAO="OK (Up to date)"
    fi
fi

echo ""
echo "[2] OPEN PORTS AND LISTENING SERVICES..."
if command -v ss > /dev/null; then
    # Using -H to omit headers and awk delimited by spaces for better resilience
    ss -H -tulnp | awk '{print $1" "$5" "$7}' || echo "No listening services."
    REL_PORTAS="Analyzed (ss)"
elif command -v netstat > /dev/null; then
    netstat -tulnp | grep -E '^tcp|^udp' || echo "No listening services."
    REL_PORTAS="Analyzed (netstat)"
else
    echo "❌ Neither 'ss' nor 'netstat' found."
    REL_PORTAS="Failed (Missing commands)"
    ALERTA_CRITICO=$((ALERTA_CRITICO + 1))
fi

echo ""
echo "[3] FIREWALL STATUS (UFW)..."
if command -v ufw > /dev/null; then
    if ufw status | grep -qi "inactive"; then
        echo "⚠️ UFW (Firewall) is INACTIVE. The server is fully exposed."
        if ask_yes_no "Do you want to ACTIVATE the firewall now (A secure restrictive policy will be applied)?" "y"; then
            echo "Configuring base policy..."
            ufw default deny incoming > /dev/null 2>&1
            ufw default allow outgoing > /dev/null 2>&1
            ufw allow 80/tcp > /dev/null 2>&1
            ufw allow 443/tcp > /dev/null 2>&1

            if [ "$SSH_INSTALLED" -eq 1 ]; then
                ufw allow 22/tcp > /dev/null 2>&1
                echo "ℹ️ SSH detected. Ports 22, 80, and 443 allowed by default."
            else
                echo "ℹ️ No SSH server detected. Ports 80 and 443 allowed by default."
            fi

            if ufw --force enable > /dev/null 2>&1; then
                echo "✅ UFW successfully activated."
                REL_FIREWALL="OK (Activated now)"
            else
                echo "❌ Error activating UFW."
                REL_FIREWALL="Failed to activate"
                ALERTA_CRITICO=$((ALERTA_CRITICO + 1))
            fi
        else
            echo "❌ Firewall kept inactive."
            REL_FIREWALL="Inactive (Vulnerable)"
            ALERTA_CRITICO=$((ALERTA_CRITICO + 1))
        fi
    fi

    # Review block
    if ! ufw status | grep -qi "inactive"; then
        echo "✅ UFW is ACTIVE."
        ufw default deny incoming > /dev/null 2>&1
        ufw default allow outgoing > /dev/null 2>&1

        echo ""
        echo "📌 The following INPUT rules are currently ALLOWED:"
        ufw status | grep "ALLOW" | grep -v "(v6)" || echo "  -> No explicit allow rules found."
        echo ""

        if [ "$AUTO_MODE" -eq 0 ]; then
            # Loop to CLOSE ports
            while true; do
                ask_input "Do you want to BLOCK/CLOSE any port listed above? (Type the port or 'N' to skip): " PORTA_BLOCK
                if [[ -z "$PORTA_BLOCK" || "$PORTA_BLOCK" =~ ^[Nn]$ ]]; then break; fi
                ufw delete allow "$PORTA_BLOCK" > /dev/null 2>&1
                ufw delete allow "${PORTA_BLOCK}/tcp" > /dev/null 2>&1
                ufw delete allow "${PORTA_BLOCK}/udp" > /dev/null 2>&1
                ufw deny "$PORTA_BLOCK" > /dev/null 2>&1
                echo "✅ Port $PORTA_BLOCK closed."
            done

            # Loop to OPEN ports
            while true; do
                ask_input "Do you want to OPEN any new port? (Type the port or 'N' to skip): " PORTA_EXTRA
                if [[ -z "$PORTA_EXTRA" || "$PORTA_EXTRA" =~ ^[Nn]$ ]]; then break; fi
                ufw allow "$PORTA_EXTRA" > /dev/null 2>&1
                echo "✅ Port $PORTA_EXTRA allowed."
            done
        fi
        [ "$REL_FIREWALL" == "Pending" ] && REL_FIREWALL="OK (Active and Reviewed)"
    fi
elif command -v iptables > /dev/null; then
    echo "⚠️ UFW not found. Checking 'iptables'."
    iptables -L -n | head -n 5
    REL_FIREWALL="Warning (Only raw iptables found)"
else
    echo "❌ No firewall manager found."
    REL_FIREWALL="Missing"
    ALERTA_CRITICO=$((ALERTA_CRITICO + 1))
fi

echo ""
echo "[4] APPARMOR STATUS (Process isolation)..."
if systemctl is-active --quiet apparmor; then
    echo "✅ AppArmor is running."
    REL_APPARMOR="OK (Active)"
else
    echo "⚠️ AppArmor is NOT active."
    if command -v apparmor_status > /dev/null; then
        if ask_yes_no "Do you want to ACTIVATE the AppArmor service now?" "y"; then
            systemctl enable --now apparmor
            echo "✅ AppArmor activated."
            REL_APPARMOR="OK (Activated now)"
        else
            echo "❌ AppArmor kept inactive."
            REL_APPARMOR="Inactive (Warning)"
        fi
    else
        REL_APPARMOR="Missing"
    fi
fi

echo ""
echo "[5] SSH SECURITY..."
if [ "$SSH_INSTALLED" -eq 1 ]; then
    SSH_CONF=$(find /etc/ssh -name "sshd_config" -type f 2>/dev/null | head -n 1)
    if [ -n "$SSH_CONF" ]; then
        ROOT_LOGIN=$(grep -E "^PermitRootLogin" "$SSH_CONF")
        if [ -z "$ROOT_LOGIN" ] || echo "$ROOT_LOGIN" | grep -q "yes"; then
            echo "⚠️ Root login configuration ALLOWS access or is NOT explicitly set."
            if ask_yes_no "Do you want to set 'PermitRootLogin no' to block root access via SSH?" "y"; then
                cp "$SSH_CONF" "${SSH_CONF}.bak_auditoria" # Security backup
                sed -i '/^PermitRootLogin/d' "$SSH_CONF"
                echo "PermitRootLogin no" >> "$SSH_CONF"

                # Tests config before restarting
                if sshd -t; then
                    systemctl restart ssh 2>/dev/null || systemctl restart sshd
                    echo "✅ Root login blocked and SSH restarted."
                    REL_SSH="OK (Blocked now)"
                else
                    echo "❌ SSH syntax error after editing. Reverting file!"
                    mv "${SSH_CONF}.bak_auditoria" "$SSH_CONF"
                    REL_SSH="Error in SSH config"
                    ALERTA_CRITICO=$((ALERTA_CRITICO + 1))
                fi
            else
                REL_SSH="Vulnerable (Root allowed)"
                ALERTA_CRITICO=$((ALERTA_CRITICO + 1))
            fi
        else
            echo "✅ Current secure configuration: $ROOT_LOGIN"
            REL_SSH="OK (Root blocked)"
        fi
    else
        REL_SSH="Conf file missing"
    fi
else
    echo "ℹ️ The SSH server (openssh-server) is not installed on the system."
    REL_SSH="Not installed (Safe)"
fi

echo ""
echo "[6] BRUTE FORCE PROTECTION (Fail2Ban)..."
FAIL2BAN_INSTALLED=0
if command -v fail2ban-client > /dev/null || dpkg-query -W -f='${Status}' fail2ban 2>/dev/null | grep -q "ok installed"; then
    echo "✅ Fail2Ban is already installed."
    FAIL2BAN_INSTALLED=1
else
    echo "⚠️ Fail2Ban is NOT installed."
    if ask_yes_no "Do you want to INSTALL Fail2Ban now?" "y"; then
        echo "Installing Fail2Ban..."
        if apt-get install -y fail2ban >/dev/null 2>&1; then
            FAIL2BAN_INSTALLED=1
        else
            echo "❌ Error installing Fail2Ban."
        fi
    fi

    if [ "$FAIL2BAN_INSTALLED" -eq 0 ]; then
        echo "❌ Fail2Ban installation skipped or with error."
        REL_FAIL2BAN="Missing (Vulnerable)"
        ALERTA_CRITICO=$((ALERTA_CRITICO + 1))
    fi
fi

if [ "$FAIL2BAN_INSTALLED" -eq 1 ]; then
    if [ "$SSH_INSTALLED" -eq 1 ]; then
        if [ ! -d "/etc/fail2ban/jail.d" ]; then
            mkdir -p /etc/fail2ban/jail.d
        fi

        # Only injects if the rule doesn't exist to avoid breaking advanced user configs
        if ! grep -Rqi "^\[sshd\]" /etc/fail2ban/jail.local /etc/fail2ban/jail.d/ 2>/dev/null; then
            cat <<EOF > /etc/fail2ban/jail.d/99-auditoria-sshd.conf
[sshd]
enabled = true
maxretry = 3
EOF
        fi

        if systemctl restart fail2ban >/dev/null 2>&1 && systemctl is-active --quiet fail2ban; then
            printf "\n\033[1;33m⚠️ WARNING: Fail2Ban ACTIVE protecting SSH!\033[0m\n"
            REL_FAIL2BAN="OK (Active)"
        else
            echo "❌ Error starting the Fail2Ban service."
            REL_FAIL2BAN="Service Error"
            ALERTA_CRITICO=$((ALERTA_CRITICO + 1))
        fi
    else
        printf "\n\033[1;33m⚠️ WARNING: Fail2Ban is installed, but there is no SSH to focus the rules on.\033[0m\n"
        REL_FAIL2BAN="OK (Installed)"
    fi
fi

echo ""
echo "[7] FAILED LOGIN ATTEMPTS (Last 10)..."
if [ "$SSH_INSTALLED" -eq 1 ]; then
    if command -v journalctl > /dev/null; then
        journalctl -u ssh.service -u sshd.service --grep="Failed password" --no-pager 2>/dev/null | tail -n 10 || echo "✅ No recent failures found."
    else
        AUTH_LOG=$(find /var/log -name "auth.log" -type f 2>/dev/null | head -n 1)
        if [ -n "$AUTH_LOG" ]; then
            grep "Failed password" "$AUTH_LOG" | tail -n 10 || echo "✅ No recent failures found."
        else
             echo "⚠️ Authentication logs not found."
        fi
    fi
else
    echo "ℹ️ Check skipped, SSH server is not installed."
fi

echo ""
echo "[8] BASIC INTEGRITY CHECK..."
if ! command -v debsums > /dev/null; then
    echo "⚠️ 'debsums' is not installed."
    if ask_yes_no "Do you want to INSTALL debsums to check system integrity?" "n"; then
        apt-get install -y debsums >/dev/null 2>&1
    else
        REL_INTEGRIDADE="Not analyzed (missing)"
    fi
fi

if command -v debsums > /dev/null; then
    PULAR_DEBSUMS="N"

    if [ "$AUTO_MODE" -eq 1 ]; then
        echo "Automatic mode: Starting integrity scan (may take a while)..."
    else
        echo "⚠️ This step may take a few minutes to complete."
        for i in {10..1}; do
            echo -ne "\rPress ENTER now to SKIP, or wait \033[1;33m${i}s\033[0m to start the scan... "
            if read -t 1; then PULAR_DEBSUMS="S"; break; fi
        done
        echo -ne "\r\033[K"
    fi

    if [ "$PULAR_DEBSUMS" == "S" ]; then
        echo "❌ Integrity check skipped by user."
        [ "$REL_INTEGRIDADE" == "Pending" ] && REL_INTEGRIDADE="Not analyzed (Skipped)"
    else
        echo "Running debsums (Looking for altered binaries)..."
        TOTAL_ARQUIVOS=$(find /var/lib/dpkg/info -name "*.md5sums" -exec cat {} + 2>/dev/null | wc -l)
        [ -z "$TOTAL_ARQUIVOS" ] || [ "$TOTAL_ARQUIVOS" -eq 0 ] && TOTAL_ARQUIVOS=50000

        FALHAS_TEMP=$(mktemp)
        debsums 2>&1 | awk -v total="$TOTAL_ARQUIVOS" -v falhas_file="$FALHAS_TEMP" '
        {
            c++
            if ($NF == "FAILED" || $NF == "missing") { print $0 >> falhas_file }
            if (c % 200 == 0 || c >= total) {
                pct = int((c / total) * 100); if (pct > 100) pct = 100
                bar_len = 40; filled = int((pct * bar_len) / 100); empty = bar_len - filled
                bar = ""; for(i=1; i<=filled; i++) bar = bar "█"; for(i=1; i<=empty; i++) bar = bar "░"
                color = (pct < 80) ? "\033[1;33m" : "\033[1;32m"
                printf "\rProgress: [%s%s\033[0m] %d%%", color, bar, pct
            }
        }
        END {
            bar = ""; for(i=1; i<=40; i++) bar = bar "█"
            printf "\rProgress: [\033[1;32m%s\033[0m] 100%%\n", bar
        }'

        if [ -s "$FALHAS_TEMP" ]; then
            echo "❌ ALERT! Altered files detected:"
            head -n 10 "$FALHAS_TEMP"
            REL_INTEGRIDADE="ALERT (Altered files)"
            ALERTA_CRITICO=$((ALERTA_CRITICO + 1))
        else
            echo "✅ No system files were maliciously modified."
            REL_INTEGRIDADE="OK (Intact)"
        fi
        rm -f "$FALHAS_TEMP"
    fi
fi

echo ""
echo "[9] ANTIVIRUS CHECK (ClamAV)..."
if command -v clamscan > /dev/null || command -v freshclam > /dev/null; then
    echo "✅ ClamAV antivirus detected."

    # Safe parsing of version and date
    CLAM_VER=$(clamscan -V 2>/dev/null || true)
    if [ -n "$CLAM_VER" ]; then
        echo "   -> Signatures installed: $CLAM_VER"
    fi

    if systemctl is-active --quiet clamav-freshclam; then
        echo "✅ The automatic service (freshclam) is ON."
        if ask_yes_no "Do you want to FORCE the download of the latest signatures now?" "n"; then
            systemctl stop clamav-freshclam 2>/dev/null
            freshclam
            systemctl start clamav-freshclam 2>/dev/null
            echo "✅ Signatures successfully updated!"
        fi
        REL_ANTIVIRUS="Inst. and Updating"
    else
        echo "⚠️ Service 'freshclam' is inactive."
        if ask_yes_no "Do you want to ACTIVATE automatic signature updates now?" "y"; then
            systemctl enable --now clamav-freshclam >/dev/null 2>&1
            REL_ANTIVIRUS="Inst. and Updating"
        else
            REL_ANTIVIRUS="Warning (No auto-update)"
        fi
    fi

    TEM_SCAN=0
    INFO_AGENDAMENTO=""

    # Safe parsing ignoring comments
    CRON_ETC=$(grep -R -i "clam" /etc/cron* 2>/dev/null | grep -v "^#" | grep -v "freshclam" | grep -v "README" | head -n 1)
    if [ -n "$CRON_ETC" ]; then
        TEM_SCAN=1
        INFO_AGENDAMENTO="Via global rule"
    fi

    if [ "$TEM_SCAN" -eq 0 ]; then
        for u in $(cut -d: -f1 /etc/passwd); do
            USER_CRON=$(crontab -u "$u" -l 2>/dev/null | grep -v "^#" | grep -i "clam" | grep -v "freshclam" | head -n 1)
            if [ -n "$USER_CRON" ]; then
                TEM_SCAN=1
                INFO_AGENDAMENTO="Via Crontab of user $u"
                break
            fi
        done
    fi

    if [ "$TEM_SCAN" -eq 0 ]; then
        TIMER_CLAM=$(systemctl list-timers --all 2>/dev/null | grep -i clam | grep -v freshclam | head -n 1)
        if [ -n "$TIMER_CLAM" ]; then
            TEM_SCAN=1
            INFO_AGENDAMENTO="Via Systemd Timer"
        fi
    fi

    if [ "$TEM_SCAN" -eq 1 ]; then
         REL_ANTIVIRUS="$REL_ANTIVIRUS | Scan Active ($INFO_AGENDAMENTO)"
    else
         echo "⚠️ No disk scan scheduled on your system."
         REL_ANTIVIRUS="$REL_ANTIVIRUS | No scan scheduled"
    fi
else
    echo "⚠️ No antivirus (ClamAV) found on the system."
    REL_ANTIVIRUS="Missing"
fi

echo ""
echo "[10] ROOTKIT HUNTER CHECK..."
# rkhunter
if command -v rkhunter > /dev/null; then
    if [ -f /etc/cron.daily/rkhunter ]; then REL_ROOTKIT="rkhunter: Active (Daily)"
    elif [ -f /etc/cron.weekly/rkhunter ]; then REL_ROOTKIT="rkhunter: Active (Weekly)"
    else REL_ROOTKIT="rkhunter: No schedule"; fi
fi

# chkrootkit
if command -v chkrootkit > /dev/null; then
    CHK_CMD=$(command -v chkrootkit)
    CHK_STATUS="No schedule"

    if [ -f /etc/cron.d/chkrootkit_auditoria ]; then
        CHK_STATUS="Active (via cron.d configured)"
    elif grep -q 'RUN_DAILY="true"' /etc/chkrootkit.conf 2>/dev/null; then
        CHK_STATUS="Active (Daily via default conf)"
    else
        echo "⚠️ chkrootkit does not have automatic scanning configured."
        if ask_yes_no "Do you want to schedule the automatic chkrootkit scan now?" "y"; then
            if [ -d "/etc/cron.d" ]; then
                ask_input "How many days between runs? (e.g., 1 for daily): " FREQ_DIAS
                ask_input "What time do you want to run it? (Format HH:MM, e.g., 03:00): " FREQ_HORA
                [ -z "$FREQ_DIAS" ] && FREQ_DIAS=1
                [ -z "$FREQ_HORA" ] && FREQ_HORA="03:00"

                HH=$(echo "$FREQ_HORA" | cut -d: -f1)
                MM=$(echo "$FREQ_HORA" | cut -d: -f2)
                DIA_CRON=$( [ "$FREQ_DIAS" = "1" ] && echo "*" || echo "*/$FREQ_DIAS" )

                echo "$MM $HH $DIA_CRON * * root $CHK_CMD -q > /var/log/chkrootkit_cron.log 2>&1" > /etc/cron.d/chkrootkit_auditoria
                echo "✅ Scheduling created for $HH:$MM."
                CHK_STATUS="Active (Created now)"
            else
                echo "❌ Directory /etc/cron.d does not exist. Scheduling failed."
            fi
        fi
    fi
    [ -z "$REL_ROOTKIT" ] && REL_ROOTKIT="chkrootkit: $CHK_STATUS" || REL_ROOTKIT="$REL_ROOTKIT | chkrootkit: $CHK_STATUS"
fi

[ -z "$REL_ROOTKIT" ] && REL_ROOTKIT="Missing"

echo ""
echo "[11] MAPPING OUTGOING CONNECTIONS (ESTABLISHED)..."
if command -v ss > /dev/null; then
    ss -H -tunpa | grep ESTAB | awk '{print $5" "$6}' | while read -r local_peer proc_info; do
        PORTA_DESTINO=$(echo "$local_peer" | awk -F: '{print $NF}')
        # Using grep or sed match to isolate the PID more safely than strict awk
        PID=$(echo "$proc_info" | grep -oP 'pid=\K\d+')
        PROG=$(echo "$proc_info" | grep -oP '("\K[^"]+)')
        if [ -n "$PID" ]; then
            CAMINHO=$(readlink -f /proc/$PID/exe 2>/dev/null || echo "Unknown")
            echo "Destination Port: $PORTA_DESTINO | Prog: ${PROG:-Kernel} | Path: $CAMINHO" >> "$LISTA_CONEXOES"
        fi
    done
elif command -v netstat > /dev/null; then
    netstat -tunpa 2>/dev/null | grep ESTABLISHED | while read -r _ _ _ _ peer state proc; do
        PORTA_DESTINO=$(echo "$peer" | awk -F: '{print $NF}')
        PID=$(echo "$proc" | cut -d/ -f1)
        PROG=$(echo "$proc" | cut -d/ -f2)
        if [[ "$PID" =~ ^[0-9]+$ ]]; then
            CAMINHO=$(readlink -f /proc/$PID/exe 2>/dev/null || echo "Unknown")
            echo "Destination Port: $PORTA_DESTINO | Prog: $PROG | Path: $CAMINHO" >> "$LISTA_CONEXOES"
        fi
    done
fi

if [ ! -s "$LISTA_CONEXOES" ]; then
    echo "No external connections established at the moment." >> "$LISTA_CONEXOES"
else
    sort -u "$LISTA_CONEXOES" -o "$LISTA_CONEXOES"
fi

echo ""
echo "=============================================="
echo "          FINAL AUDIT REPORT                  "
echo "=============================================="
echo "• OS Updates          : $REL_ATUALIZACAO"
echo "• Ports and Services  : $REL_PORTAS"
echo "• Firewall            : $REL_FIREWALL"
echo "• AppArmor (MAC)      : $REL_APPARMOR"
echo "• SSH Hardening       : $REL_SSH"
echo "• Fail2Ban (Blocking) : $REL_FAIL2BAN"
echo "• System Integrity    : $REL_INTEGRIDADE"
echo "• Antivirus           : $REL_ANTIVIRUS"
echo "• Rootkit Hunter      : $REL_ROOTKIT"
echo "----------------------------------------------"
echo "     ESTABLISHED OUTGOING CONNECTIONS         "
echo "----------------------------------------------"
cat "$LISTA_CONEXOES"
echo "----------------------------------------------"

if [ "$ALERTA_CRITICO" -gt 0 ]; then
    echo "FINAL CONCLUSION: The system has $ALERTA_CRITICO critical attention point(s)!"
    echo "Recommended action: Review the options marked as 'Vulnerable' or 'Alert'."
else
    echo "FINAL CONCLUSION: Excellent! Your system has the main defense layers active."
fi
echo "=============================================="
rm -f "$LISTA_CONEXOES"
