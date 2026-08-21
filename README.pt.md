**English** | [Portuguese](README.pt.md)

# 🔒 Auditoria de Segurança e Hardening (v23)

Um script Bash profissional e resiliente para auditar e fortalecer a segurança de servidores Linux (Debian/Ubuntu). Executa verificações críticas de segurança e aplica correções de hardening de forma interativa ou automática.

## ✨ Funcionalidades

O script realiza 11 etapas de verificação e endurecimento do sistema:

1.  **🔍 Atualizações Pendentes**: Verifica e aplica atualizações de segurança do sistema operacional.
2.  **🔌 Portas e Serviços**: Lista portas abertas e serviços em escuta (usando `ss` ou `netstat`).
3.  **🛡️ Firewall (UFW)**: Verifica se o UFW está ativo, configura políticas restritivas, e permite revisão interativa de regras.
4.  **🔒 AppArmor**: Garante que o sistema de isolamento de processos Mandatory Access Control (MAC) esteja ativo.
5.  **🔑 Hardening do SSH**: Bloqueia login como root, testa a configuração antes de reiniciar o serviço e cria backup automático.
6.  **⛔ Proteção contra Força Bruta (Fail2Ban)**: Instala e configura o Fail2Ban para proteger o SSH (bloqueia IP após 3 tentativas).
7.  **📜 Tentativas de Login Falhas**: Exibe as últimas tentativas de senha inválidas no SSH.
8.  **✅ Integridade do Sistema**: Usa o `debsums` para verificar a integridade de binários e bibliotecas, com barra de progresso.
9.  **🦠 Antivírus (ClamAV)**: Verifica a instalação, atualização de vacinas e agendamento de varreduras do ClamAV.
10. **🎯 Rootkit Hunter**: Detecta a presença de ferramentas como `rkhunter` e `chkrootkit` e seus agendamentos.
11. **🌐 Conexões de Saída**: Mapeia todas as conexões externas estabelecidas, identificando processos e portas de destino.

Ao final, um relatório consolidado é exibido com o status de cada camada de defesa e uma conclusão final sobre a postura de segurança do sistema.

## ⚙️ Modos de Execução

O script oferece dois modos principais:

- **Modo Interativo (Padrão)**: Faz perguntas ao usuário (`y/n`) para cada ação corretiva. Permite controle total sobre o que será alterado no sistema.
- **Modo Automático (`--auto` ou `-y`)**: Não requer nenhuma interação. Aplica automaticamente as melhores práticas de segurança padrão (ativa firewall, instala e configura Fail2Ban, bloqueia root SSH, ativa AppArmor, etc.). Ideal para setups iniciais ou automação via scripts de provisionamento (cloud-init, Ansible, etc.).

## 📋 Pré-requisitos
[![Portuguese](https://img.shields.io/badge/PT-red)](README.pt.md)
[![English](https://img.shields.io/badge/English-blue)](README.md)

- Sistema operacional **Debian** ou **Ubuntu** (ou derivados que usem `apt`).
- **Bash** (padrão em todos os sistemas Linux).
- Privilégios de **root** (sudo).

## 🚀 Como Usar

### 1. Download e Permissão

Clone o repositório ou faça o download do script, e conceda permissão de execução:

```bash
wget https://raw.githubusercontent.com/seu-usuario/seu-repo/main/auditoria_hardening.sh
# ou
curl -O https://raw.githubusercontent.com/seu-usuario/seu-repo/main/auditoria_hardening.sh

chmod +x auditoria_hardening.sh
```

### 2. Execução

> **⚠️ Importante:** Sempre execute o script como superusuário.

**A. Modo Interativo (padrão):**

```bash
sudo bash auditoria_hardening.sh
```

Você será guiado passo a passo, podendo decidir cada ação corretiva.

**B. Modo Automático (não interativo):**

```bash
sudo bash auditoria_hardening.sh --auto
# ou
sudo bash auditoria_hardening.sh -y
```

O script aplicará todas as configurações de segurança automaticamente. Veja a seção "Comportamento no Modo Automático" abaixo.

## 🤖 Comportamento no Modo Automático (`--auto`)

Quando executado com `--auto`, o script assume as seguintes decisões:

| Ação/Configuração                       | Decisão Automática           |
|-----------------------------------------|------------------------------|
| Atualizar pacotes do sistema            | **Não** (apenas verifica)    |
| Ativar Firewall (UFW)                   | **Sim** (portas 80, 443, 22) |
| Ativar AppArmor                         | **Sim**                      |
| Bloquear login root no SSH              | **Sim**                      |
| Instalar e configurar Fail2Ban          | **Sim**                      |
| Verificar integridade com `debsums`     | **Sim** (completa)           |
| Ativar atualização automática ClamAV    | **Sim**                      |
| Agendar chkrootkit                      | **Sim** (diário às 03:00)    |

**É seguro para uma configuração inicial, mas em ambientes com regras de firewall complexas, recomenda-se o modo interativo para revisão cuidadosa.**

## 🧠 Estrutura do Código

- **Validação Inicial**: Garante execução como Bash e com privilégios de root.
- **Funções Auxiliares**: `ask_yes_no` e `ask_input` padronizam a interação e suportam o modo automático.
- **Checagens Modulares**: Cada etapa (atualizações, firewall, SSH, etc.) é um bloco independente.
- **Relatório Consolidado**: Variáveis armazenam o status de cada etapa para o sumário final.
- **Limpeza**: Arquivos temporários são criados com `mktemp` e removidos ao final.

## 📝 Exemplo de Saída (Relatório Final)

```text
==============================================
          RELATÓRIO FINAL DE AUDITORIA
==============================================
• Atualizações do SO  : OK (Atualizado)
• Portas e Serviços   : Analisado (ss)
• Firewall            : OK (Ativo e Revisado)
• AppArmor (MAC)      : OK (Ativo)
• Hardening SSH       : OK (Root bloqueado)
• Fail2Ban (Bloqueio) : OK (Ativo)
• Integridade Sistema : OK (Íntegro)
• Antivírus           : Instal. e Atualizando | Scan Ativo (Via regra global)
• Rootkit Hunter      : rkhunter: Ativo (Diário) | chkrootkit: Ativo (Diário)
----------------------------------------------
       CONEXÕES DE SAÍDA ESTABELECIDAS
----------------------------------------------
Porta Destino: 443 | Prog: curl | Local: /usr/bin/curl
Porta Destino: 53  | Prog: systemd-resolve | Local: /usr/lib/systemd/systemd-resolved
----------------------------------------------
CONCLUSÃO FINAL: Excelente! Seu sistema está com as principais camadas de defesa ativas.
==============================================
```

## 💡 Recomendações Pós-Execução

- **Revise as regras do Firewall**: Execute `sudo ufw status` para conferir as portas liberadas.
- **Teste o acesso SSH**: Se bloqueou o root, certifique-se de ter um usuário comum com `sudo` configurado antes de fechar a sessão atual.
- **Monitore os Logs**: Acompanhe `/var/log/auth.log` e `fail2ban-client status` para verificar bloqueios em ação.
- **Execute periodicamente**: Inclua o script no cron (apenas o modo `--auto` para verificações) ou execute-o manualmente após mudanças no sistema.

---

## 🔗 Contribuição

Sinta-se à vontade para abrir **Issues** para bugs/sugestões ou enviar **Pull Requests**. Toda ajuda é bem-vinda para tornar este script ainda mais robusto!

**Licença**: MIT
