#!/bin/bash

# ==============================================================================
# AUDITORIA DE SEGURANÇA E HARDENING (v23 - Professional & Resilient Edition)
# ==============================================================================

# Validação do Bash (Garante suporte a arrays, read -t e formatações avançadas)
[ -n "$BASH_VERSION" ] || { echo "Erro: Este script exige o BASH. Execute com: sudo bash $0"; exit 1; }

# Garante privilégios de root
if [ "$EUID" -ne 0 ]; then
  echo "Por favor, execute como root (sudo $0)."
  exit 1
fi

# Detecta modo Não-Interativo (--auto ou -y)
AUTO_MODE=0
if [[ "$1" == "--auto" || "$1" == "-y" ]]; then
    AUTO_MODE=1
    echo "⚠️ MODO AUTOMÁTICO ATIVADO: O script não pedirá confirmações e aplicará regras de segurança padrão."
    sleep 2
fi

echo "=============================================="
echo "  AUDITORIA DE SEGURANÇA E HARDENING          "
echo "  Data: $(date '+%Y-%m-%d %H:%M:%S')          "
echo "=============================================="

# Variáveis Globais
REL_ATUALIZACAO="Pendente"
REL_PORTAS="Pendente"
REL_FIREWALL="Pendente"
REL_APPARMOR="Pendente"
REL_SSH="Pendente"
REL_FAIL2BAN="Pendente"
REL_INTEGRIDADE="Pendente"
REL_ANTIVIRUS="Pendente"
REL_ROOTKIT=""
ALERTA_CRITICO=0
LISTA_CONEXOES=$(mktemp)

# ==============================================================================
# FUNÇÕES AUXILIARES
# ==============================================================================

# Pergunta padronizada com loop e suporte ao modo automático
ask_yes_no() {
    local prompt="$1"
    local default_auto="$2" # "y" ou "n" para o modo auto
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
            * ) echo -e "\033[1;31mPor favor, responda com 'y' (sim) ou 'n' (não).\033[0m" ;;
        esac
    done
}

# Pergunta para dados customizados (ex: Portas)
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

# Verifica se o SERVIDOR SSH está instalado (ignora o cliente)
SSH_INSTALLED=0
if [ -x "/usr/sbin/sshd" ] || dpkg-query -W -f='${Status}' openssh-server 2>/dev/null | grep -q "ok installed"; then
    SSH_INSTALLED=1
fi

# ==============================================================================
# INÍCIO DAS CHECAGENS
# ==============================================================================

echo ""
echo "[1] VERIFICANDO ATUALIZAÇÕES PENDENTES..."
if ! apt-get update -qq; then
    echo "⚠️ Falha ao conectar aos repositórios (Problema de rede ou APT lock). O script continuará."
    REL_ATUALIZACAO="Falha de Rede/APT"
    ALERTA_CRITICO=$((ALERTA_CRITICO + 1))
else
    UPGRADES=$(apt-get -s upgrade 2>/dev/null | grep -P '^\d+ upgraded' | awk '{print $1}')
    if [ -n "$UPGRADES" ] && [ "$UPGRADES" -gt 0 ]; then
        echo "⚠️ ATENÇÃO: Existem $UPGRADES pacotes precisando de atualização."
        if ask_yes_no "Deseja atualizar o sistema agora? (Executar 'apt upgrade -y')" "n"; then
            echo "Atualizando pacotes... Isso pode levar alguns minutos."
            if apt-get upgrade -y; then
                echo "✅ Sistema atualizado com sucesso."
                REL_ATUALIZACAO="OK (Atualizado agora)"
            else
                echo "❌ Falha durante a atualização."
                REL_ATUALIZACAO="Erro durante Atualização"
                ALERTA_CRITICO=$((ALERTA_CRITICO + 1))
            fi
        else
            echo "❌ Atualização ignorada."
            REL_ATUALIZACAO="Desatualizado ($UPGRADES pacotes)"
            ALERTA_CRITICO=$((ALERTA_CRITICO + 1))
        fi
    else
        echo "✅ Sistema já está atualizado."
        REL_ATUALIZACAO="OK (Atualizado)"
    fi
fi

echo ""
echo "[2] PORTAS ABERTAS E SERVIÇOS ESCUTANDO..."
if command -v ss > /dev/null; then
    # Usando -H para omitir cabeçalhos e awk delimitando por espaços para ser mais resiliente
    ss -H -tulnp | awk '{print $1" "$5" "$7}' || echo "Nenhum serviço em escuta."
    REL_PORTAS="Analisado (ss)"
elif command -v netstat > /dev/null; then
    netstat -tulnp | grep -E '^tcp|^udp' || echo "Nenhum serviço em escuta."
    REL_PORTAS="Analisado (netstat)"
else
    echo "❌ Nem 'ss' nem 'netstat' encontrados."
    REL_PORTAS="Falha (Comandos ausentes)"
    ALERTA_CRITICO=$((ALERTA_CRITICO + 1))
fi

echo ""
echo "[3] STATUS DO FIREWALL (UFW)..."
if command -v ufw > /dev/null; then
    if ufw status | grep -qi "inactive"; then
        echo "⚠️ O UFW (Firewall) está INATIVO. O servidor está totalmente exposto."
        if ask_yes_no "Deseja ATIVAR o firewall agora (Será aplicada política restritiva segura)?" "y"; then
            echo "Configurando política base..."
            ufw default deny incoming > /dev/null 2>&1
            ufw default allow outgoing > /dev/null 2>&1
            ufw allow 80/tcp > /dev/null 2>&1
            ufw allow 443/tcp > /dev/null 2>&1

            if [ "$SSH_INSTALLED" -eq 1 ]; then
                ufw allow 22/tcp > /dev/null 2>&1
                echo "ℹ️ SSH detectado. Portas 22, 80 e 443 liberadas por padrão."
            else
                echo "ℹ️ Nenhum servidor SSH detectado. Portas 80 e 443 liberadas por padrão."
            fi

            if ufw --force enable > /dev/null 2>&1; then
                echo "✅ UFW ativado com sucesso."
                REL_FIREWALL="OK (Ativado agora)"
            else
                echo "❌ Erro ao ativar o UFW."
                REL_FIREWALL="Falha ao ativar"
                ALERTA_CRITICO=$((ALERTA_CRITICO + 1))
            fi
        else
            echo "❌ Firewall mantido inativo."
            REL_FIREWALL="Inativo (Vulnerável)"
            ALERTA_CRITICO=$((ALERTA_CRITICO + 1))
        fi
    fi

    # Bloco de revisão
    if ! ufw status | grep -qi "inactive"; then
        echo "✅ UFW está ATIVO."
        ufw default deny incoming > /dev/null 2>&1
        ufw default allow outgoing > /dev/null 2>&1

        echo ""
        echo "📌 As seguintes regras de ENTRADA estão PERMITIDAS atualmente:"
        ufw status | grep "ALLOW" | grep -v "(v6)" || echo "  -> Nenhuma regra explícita de permissão encontrada."
        echo ""

        if [ "$AUTO_MODE" -eq 0 ]; then
            # Loop para FECHAR portas
            while true; do
                ask_input "Deseja BLOQUEAR/FECHAR alguma porta listada acima? (Digite a porta ou 'N' para pular): " PORTA_BLOCK
                if [[ -z "$PORTA_BLOCK" || "$PORTA_BLOCK" =~ ^[Nn]$ ]]; then break; fi
                ufw delete allow "$PORTA_BLOCK" > /dev/null 2>&1
                ufw delete allow "${PORTA_BLOCK}/tcp" > /dev/null 2>&1
                ufw delete allow "${PORTA_BLOCK}/udp" > /dev/null 2>&1
                ufw deny "$PORTA_BLOCK" > /dev/null 2>&1
                echo "✅ Porta $PORTA_BLOCK fechada."
            done

            # Loop para ABRIR portas
            while true; do
                ask_input "Deseja ABRIR alguma nova porta? (Digite a porta ou 'N' para pular): " PORTA_EXTRA
                if [[ -z "$PORTA_EXTRA" || "$PORTA_EXTRA" =~ ^[Nn]$ ]]; then break; fi
                ufw allow "$PORTA_EXTRA" > /dev/null 2>&1
                echo "✅ Porta $PORTA_EXTRA liberada."
            done
        fi
        [ "$REL_FIREWALL" == "Pendente" ] && REL_FIREWALL="OK (Ativo e Revisado)"
    fi
elif command -v iptables > /dev/null; then
    echo "⚠️ UFW não encontrado. Checando 'iptables'."
    iptables -L -n | head -n 5
    REL_FIREWALL="Aviso (Apenas iptables bruto encontrado)"
else
    echo "❌ Nenhum gerenciador de firewall encontrado."
    REL_FIREWALL="Ausente"
    ALERTA_CRITICO=$((ALERTA_CRITICO + 1))
fi

echo ""
echo "[4] STATUS DO APPARMOR (Isolamento de processos)..."
if systemctl is-active --quiet apparmor; then
    echo "✅ AppArmor está rodando."
    REL_APPARMOR="OK (Ativo)"
else
    echo "⚠️ O AppArmor NÃO está ativo."
    if command -v apparmor_status > /dev/null; then
        if ask_yes_no "Deseja ATIVAR o serviço AppArmor agora?" "y"; then
            systemctl enable --now apparmor
            echo "✅ AppArmor ativado."
            REL_APPARMOR="OK (Ativado agora)"
        else
            echo "❌ AppArmor mantido inativo."
            REL_APPARMOR="Inativo (Aviso)"
        fi
    else
        REL_APPARMOR="Ausente"
    fi
fi

echo ""
echo "[5] SEGURANÇA DO SSH..."
if [ "$SSH_INSTALLED" -eq 1 ]; then
    SSH_CONF=$(find /etc/ssh -name "sshd_config" -type f 2>/dev/null | head -n 1)
    if [ -n "$SSH_CONF" ]; then
        ROOT_LOGIN=$(grep -E "^PermitRootLogin" "$SSH_CONF")
        if [ -z "$ROOT_LOGIN" ] || echo "$ROOT_LOGIN" | grep -q "yes"; then
            echo "⚠️ Configuração de login do root PERMITE acesso ou NÃO está explícita."
            if ask_yes_no "Deseja definir 'PermitRootLogin no' para bloquear o acesso do root via SSH?" "y"; then
                cp "$SSH_CONF" "${SSH_CONF}.bak_auditoria" # Backup de segurança
                sed -i '/^PermitRootLogin/d' "$SSH_CONF"
                echo "PermitRootLogin no" >> "$SSH_CONF"

                # Testa a configuração antes de reiniciar
                if sshd -t; then
                    systemctl restart ssh 2>/dev/null || systemctl restart sshd
                    echo "✅ Login de root bloqueado e SSH reiniciado."
                    REL_SSH="OK (Bloqueado agora)"
                else
                    echo "❌ Falha na sintaxe do SSH após edição. Revertendo arquivo!"
                    mv "${SSH_CONF}.bak_auditoria" "$SSH_CONF"
                    REL_SSH="Erro na configuração SSH"
                    ALERTA_CRITICO=$((ALERTA_CRITICO + 1))
                fi
            else
                REL_SSH="Vulnerável (Root permitido)"
                ALERTA_CRITICO=$((ALERTA_CRITICO + 1))
            fi
        else
            echo "✅ Configuração atual segura: $ROOT_LOGIN"
            REL_SSH="OK (Root bloqueado)"
        fi
    else
        REL_SSH="Arquivo conf ausente"
    fi
else
    echo "ℹ️ O servidor SSH (openssh-server) não está instalado no sistema."
    REL_SSH="Não instalado (Seguro)"
fi

echo ""
echo "[6] PROTEÇÃO CONTRA FORÇA BRUTA (Fail2Ban)..."
FAIL2BAN_INSTALLED=0
if command -v fail2ban-client > /dev/null || dpkg-query -W -f='${Status}' fail2ban 2>/dev/null | grep -q "ok installed"; then
    echo "✅ Fail2Ban já está instalado."
    FAIL2BAN_INSTALLED=1
else
    echo "⚠️ O Fail2Ban NÃO está instalado."
    if ask_yes_no "Deseja INSTALAR o Fail2Ban agora?" "y"; then
        echo "Instalando o Fail2Ban..."
        if apt-get install -y fail2ban >/dev/null 2>&1; then
            FAIL2BAN_INSTALLED=1
        else
            echo "❌ Erro ao instalar o Fail2Ban."
        fi
    fi

    if [ "$FAIL2BAN_INSTALLED" -eq 0 ]; then
        echo "❌ Instalação do Fail2Ban ignorada ou com erro."
        REL_FAIL2BAN="Ausente (Vulnerável)"
        ALERTA_CRITICO=$((ALERTA_CRITICO + 1))
    fi
fi

if [ "$FAIL2BAN_INSTALLED" -eq 1 ]; then
    if [ "$SSH_INSTALLED" -eq 1 ]; then
        if [ ! -d "/etc/fail2ban/jail.d" ]; then
            mkdir -p /etc/fail2ban/jail.d
        fi

        # Só injeta se a regra não existir para não quebrar confs avançadas do usuário
        if ! grep -Rqi "^\[sshd\]" /etc/fail2ban/jail.local /etc/fail2ban/jail.d/ 2>/dev/null; then
            cat <<EOF > /etc/fail2ban/jail.d/99-auditoria-sshd.conf
[sshd]
enabled = true
maxretry = 3
EOF
        fi

        if systemctl restart fail2ban >/dev/null 2>&1 && systemctl is-active --quiet fail2ban; then
            printf "\n\033[1;33m⚠️ AVISO: Fail2Ban ATIVO protegendo o SSH!\033[0m\n"
            REL_FAIL2BAN="OK (Ativo)"
        else
            echo "❌ Erro ao iniciar o serviço Fail2Ban."
            REL_FAIL2BAN="Erro no Serviço"
            ALERTA_CRITICO=$((ALERTA_CRITICO + 1))
        fi
    else
        printf "\n\033[1;33m⚠️ AVISO: O Fail2Ban está instalado, mas não há SSH para focar as regras.\033[0m\n"
        REL_FAIL2BAN="OK (Instalado)"
    fi
fi

echo ""
echo "[7] TENTATIVAS DE LOGIN FALHAS (Últimas 10)..."
if [ "$SSH_INSTALLED" -eq 1 ]; then
    if command -v journalctl > /dev/null; then
        journalctl -u ssh.service -u sshd.service --grep="Failed password" --no-pager 2>/dev/null | tail -n 10 || echo "✅ Nenhuma falha recente encontrada."
    else
        AUTH_LOG=$(find /var/log -name "auth.log" -type f 2>/dev/null | head -n 1)
        if [ -n "$AUTH_LOG" ]; then
            grep "Failed password" "$AUTH_LOG" | tail -n 10 || echo "✅ Nenhuma falha recente encontrada."
        else
             echo "⚠️ Logs de autenticação não localizados."
        fi
    fi
else
    echo "ℹ️ Verificação pulada, servidor SSH não está instalado."
fi

echo ""
echo "[8] VERIFICAÇÃO DE INTEGRIDADE BÁSICA..."
if ! command -v debsums > /dev/null; then
    echo "⚠️ 'debsums' não está instalado."
    if ask_yes_no "Deseja INSTALAR o debsums para verificar integridade do sistema?" "n"; then
        apt-get install -y debsums >/dev/null 2>&1
    else
        REL_INTEGRIDADE="Não analisada (ausente)"
    fi
fi

if command -v debsums > /dev/null; then
    PULAR_DEBSUMS="N"

    if [ "$AUTO_MODE" -eq 1 ]; then
        echo "Modo automático: Iniciando varredura de integridade (pode demorar)..."
    else
        echo "⚠️ Esta etapa pode demorar alguns minutos para ser concluída."
        for i in {10..1}; do
            echo -ne "\rPressione ENTER agora para PULAR, ou aguarde \033[1;33m${i}s\033[0m para iniciar a varredura... "
            if read -t 1; then PULAR_DEBSUMS="S"; break; fi
        done
        echo -ne "\r\033[K"
    fi

    if [ "$PULAR_DEBSUMS" == "S" ]; then
        echo "❌ Verificação de integridade pulada pelo usuário."
        [ "$REL_INTEGRIDADE" == "Pendente" ] && REL_INTEGRIDADE="Não analisada (Pulada)"
    else
        echo "Rodando debsums (Buscando binários alterados)..."
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
                printf "\rProgresso: [%s%s\033[0m] %d%%", color, bar, pct
            }
        }
        END {
            bar = ""; for(i=1; i<=40; i++) bar = bar "█"
            printf "\rProgresso: [\033[1;32m%s\033[0m] 100%%\n", bar
        }'

        if [ -s "$FALHAS_TEMP" ]; then
            echo "❌ ALERTA! Arquivos alterados detectados:"
            head -n 10 "$FALHAS_TEMP"
            REL_INTEGRIDADE="ALERTA (Arquivos alterados)"
            ALERTA_CRITICO=$((ALERTA_CRITICO + 1))
        else
            echo "✅ Nenhum arquivo do sistema foi modificado maliciosamente."
            REL_INTEGRIDADE="OK (Íntegro)"
        fi
        rm -f "$FALHAS_TEMP"
    fi
fi

echo ""
echo "[9] VERIFICAÇÃO DE ANTIVÍRUS (ClamAV)..."
if command -v clamscan > /dev/null || command -v freshclam > /dev/null; then
    echo "✅ Antivírus ClamAV detectado."

    # Parsing seguro da versão e data
    CLAM_VER=$(clamscan -V 2>/dev/null || true)
    if [ -n "$CLAM_VER" ]; then
        echo "   -> Vacinas instaladas: $CLAM_VER"
    fi

    if systemctl is-active --quiet clamav-freshclam; then
        echo "✅ O Serviço automático (freshclam) está LIGADO."
        if ask_yes_no "Deseja FORÇAR o download das vacinas mais recentes agora?" "n"; then
            systemctl stop clamav-freshclam 2>/dev/null
            freshclam
            systemctl start clamav-freshclam 2>/dev/null
            echo "✅ Vacinas atualizadas com sucesso!"
        fi
        REL_ANTIVIRUS="Instal. e Atualizando"
    else
        echo "⚠️ Serviço 'freshclam' está inativo."
        if ask_yes_no "Deseja ATIVAR a atualização automática de vacinas agora?" "y"; then
            systemctl enable --now clamav-freshclam >/dev/null 2>&1
            REL_ANTIVIRUS="Instal. e Atualizando"
        else
            REL_ANTIVIRUS="Aviso (Sem auto-update)"
        fi
    fi

    TEM_SCAN=0
    INFO_AGENDAMENTO=""

    # Parsing seguro ignorando comentários
    CRON_ETC=$(grep -R -i "clam" /etc/cron* 2>/dev/null | grep -v "^#" | grep -v "freshclam" | grep -v "README" | head -n 1)
    if [ -n "$CRON_ETC" ]; then
        TEM_SCAN=1
        INFO_AGENDAMENTO="Via regra global"
    fi

    if [ "$TEM_SCAN" -eq 0 ]; then
        for u in $(cut -d: -f1 /etc/passwd); do
            USER_CRON=$(crontab -u "$u" -l 2>/dev/null | grep -v "^#" | grep -i "clam" | grep -v "freshclam" | head -n 1)
            if [ -n "$USER_CRON" ]; then
                TEM_SCAN=1
                INFO_AGENDAMENTO="Via Crontab do usuário $u"
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
         REL_ANTIVIRUS="$REL_ANTIVIRUS | Scan Ativo ($INFO_AGENDAMENTO)"
    else
         echo "⚠️ Nenhuma varredura de disco agendada em seu sistema."
         REL_ANTIVIRUS="$REL_ANTIVIRUS | Sem varredura"
    fi
else
    echo "⚠️ Nenhum antivírus (ClamAV) encontrado no sistema."
    REL_ANTIVIRUS="Ausente"
fi

echo ""
echo "[10] VERIFICAÇÃO DE ROOTKIT HUNTER..."
# rkhunter
if command -v rkhunter > /dev/null; then
    if [ -f /etc/cron.daily/rkhunter ]; then REL_ROOTKIT="rkhunter: Ativo (Diário)"
    elif [ -f /etc/cron.weekly/rkhunter ]; then REL_ROOTKIT="rkhunter: Ativo (Semanal)"
    else REL_ROOTKIT="rkhunter: Sem agendamento"; fi
fi

# chkrootkit
if command -v chkrootkit > /dev/null; then
    CHK_CMD=$(command -v chkrootkit)
    CHK_STATUS="Sem agendamento"

    if [ -f /etc/cron.d/chkrootkit_auditoria ]; then
        CHK_STATUS="Ativo (via cron.d configurado)"
    elif grep -q 'RUN_DAILY="true"' /etc/chkrootkit.conf 2>/dev/null; then
        CHK_STATUS="Ativo (Diário via conf padrão)"
    else
        echo "⚠️ chkrootkit não possui varredura automática configurada."
        if ask_yes_no "Deseja agendar a varredura automática do chkrootkit agora?" "y"; then
            if [ -d "/etc/cron.d" ]; then
                ask_input "A cada quantos dias deseja rodar? (Ex: 1 para diário): " FREQ_DIAS
                ask_input "Qual horário deseja executar? (Formato HH:MM, ex: 03:00): " FREQ_HORA
                [ -z "$FREQ_DIAS" ] && FREQ_DIAS=1
                [ -z "$FREQ_HORA" ] && FREQ_HORA="03:00"

                HH=$(echo "$FREQ_HORA" | cut -d: -f1)
                MM=$(echo "$FREQ_HORA" | cut -d: -f2)
                DIA_CRON=$( [ "$FREQ_DIAS" = "1" ] && echo "*" || echo "*/$FREQ_DIAS" )

                echo "$MM $HH $DIA_CRON * * root $CHK_CMD -q > /var/log/chkrootkit_cron.log 2>&1" > /etc/cron.d/chkrootkit_auditoria
                echo "✅ Agendamento criado para as $HH:$MM."
                CHK_STATUS="Ativo (Criado agora)"
            else
                echo "❌ Diretório /etc/cron.d inexistente. Agendamento falhou."
            fi
        fi
    fi
    [ -z "$REL_ROOTKIT" ] && REL_ROOTKIT="chkrootkit: $CHK_STATUS" || REL_ROOTKIT="$REL_ROOTKIT | chkrootkit: $CHK_STATUS"
fi

[ -z "$REL_ROOTKIT" ] && REL_ROOTKIT="Ausente"

echo ""
echo "[11] MAPEANDO CONEXÕES DE SAÍDA (ESTABELECIDAS)..."
if command -v ss > /dev/null; then
    ss -H -tunpa | grep ESTAB | awk '{print $5" "$6}' | while read -r local_peer proc_info; do
        PORTA_DESTINO=$(echo "$local_peer" | awk -F: '{print $NF}')
        # Usando match do grep ou sed para isolar o PID de forma mais segura que awk estrito
        PID=$(echo "$proc_info" | grep -oP 'pid=\K\d+')
        PROG=$(echo "$proc_info" | grep -oP '("\K[^"]+)')
        if [ -n "$PID" ]; then
            CAMINHO=$(readlink -f /proc/$PID/exe 2>/dev/null || echo "Desconhecido")
            echo "Porta Destino: $PORTA_DESTINO | Prog: ${PROG:-Kernel} | Local: $CAMINHO" >> "$LISTA_CONEXOES"
        fi
    done
elif command -v netstat > /dev/null; then
    netstat -tunpa 2>/dev/null | grep ESTABLISHED | while read -r _ _ _ _ peer state proc; do
        PORTA_DESTINO=$(echo "$peer" | awk -F: '{print $NF}')
        PID=$(echo "$proc" | cut -d/ -f1)
        PROG=$(echo "$proc" | cut -d/ -f2)
        if [[ "$PID" =~ ^[0-9]+$ ]]; then
            CAMINHO=$(readlink -f /proc/$PID/exe 2>/dev/null || echo "Desconhecido")
            echo "Porta Destino: $PORTA_DESTINO | Prog: $PROG | Local: $CAMINHO" >> "$LISTA_CONEXOES"
        fi
    done
fi

if [ ! -s "$LISTA_CONEXOES" ]; then
    echo "Nenhuma conexão externa estabelecida no momento." >> "$LISTA_CONEXOES"
else
    sort -u "$LISTA_CONEXOES" -o "$LISTA_CONEXOES"
fi

echo ""
echo "=============================================="
echo "          RELATÓRIO FINAL DE AUDITORIA        "
echo "=============================================="
echo "• Atualizações do SO  : $REL_ATUALIZACAO"
echo "• Portas e Serviços   : $REL_PORTAS"
echo "• Firewall            : $REL_FIREWALL"
echo "• AppArmor (MAC)      : $REL_APPARMOR"
echo "• Hardening SSH       : $REL_SSH"
echo "• Fail2Ban (Bloqueio) : $REL_FAIL2BAN"
echo "• Integridade Sistema : $REL_INTEGRIDADE"
echo "• Antivírus           : $REL_ANTIVIRUS"
echo "• Rootkit Hunter      : $REL_ROOTKIT"
echo "----------------------------------------------"
echo "       CONEXÕES DE SAÍDA ESTABELECIDAS        "
echo "----------------------------------------------"
cat "$LISTA_CONEXOES"
echo "----------------------------------------------"

if [ "$ALERTA_CRITICO" -gt 0 ]; then
    echo "CONCLUSÃO FINAL: O sistema apresenta $ALERTA_CRITICO ponto(s) de atenção crítico(s)!"
    echo "Ação recomendada: Revise as opções marcadas como 'Vulnerável' ou 'Alerta'."
else
    echo "CONCLUSÃO FINAL: Excelente! Seu sistema está com as principais camadas de defesa ativas."
fi
echo "=============================================="
rm -f "$LISTA_CONEXOES"
