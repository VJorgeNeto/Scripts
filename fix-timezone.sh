#!/bin/bash

# ==============================================================================
# Script: fix-timezone.sh
# Descrição: Resolução definitiva de fuso horário e sincronização NTP no Oracle Linux 7
# ==============================================================================

# Cores para output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Iniciando ajuste definitivo de Timezone e NTP...${NC}\n"

# 1. Validação de Root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[ERRO] Por favor, execute este script como root ou usando sudo.${NC}"
  exit 1
fi

# 2. Desativar sincronização do VMware (Se aplicável e se a ferramenta existir)
if command -v vmware-toolbox-cmd &> /dev/null; then
    echo -e "${GREEN}[+] Desativando sincronização de tempo do VMware Tools...${NC}"
    vmware-toolbox-cmd timesync disable
else
    echo -e "${YELLOW}[-] vmware-toolbox-cmd não encontrado. Ignorando etapa do VMware.${NC}"
fi

# 3. Forçar o Timezone de São Paulo via Link Simbólico
echo -e "${GREEN}[+] Ajustando timezone para America/Sao_Paulo...${NC}"
rm -f /etc/localtime
ln -s /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime

# 4. Parar e desativar serviços conflitantes
echo -e "${GREEN}[+] Eliminando serviços de tempo conflitantes (ntpd, systemd-timesyncd)...${NC}"
systemctl stop ntpd 2>/dev/null
systemctl disable ntpd 2>/dev/null
systemctl stop systemd-timesyncd 2>/dev/null
systemctl disable systemd-timesyncd 2>/dev/null

# 5. Configuração Agressiva do Chrony
echo -e "${GREEN}[+] Configurando o Chrony com servidores do NTP.br...${NC}"

# Faz backup da configuração original
cp /etc/chrony.conf /etc/chrony.conf.bkp_$(date +%F_%H-%M-%S)

# Comenta servidores/pools existentes para evitar conflitos
sed -i 's/^server/#server/g' /etc/chrony.conf
sed -i 's/^pool/#pool/g' /etc/chrony.conf

# Verifica se os servidores do ntp.br já existem, se não, adiciona
if ! grep -q "a.st1.ntp.br" /etc/chrony.conf; then
cat <<EOF >> /etc/chrony.conf

# --- Adicionado pelo Script de Ajuste NTP ---
server a.st1.ntp.br iburst
server b.st1.ntp.br iburst
server c.st1.ntp.br iburst
server d.st1.ntp.br iburst

# Força o salto (step) se o atraso for maior que 1 segundo nos 3 primeiros updates
makestep 1.0 3

# Permite sincronização com o relógio de hardware (RTC)
rtcsync
# --------------------------------------------
EOF
fi

# 6. Reiniciar Chrony e gravar na BIOS/UEFI
echo -e "${GREEN}[+] Reiniciando o Chronyd e gravando a hora no Hardware Clock...${NC}"
systemctl restart chronyd
systemctl enable chronyd

# Aguarda 3 segundos para o chrony fazer o makestep inicial
sleep 3
hwclock --systohc

# 7. Validação Final
echo -e "\n${YELLOW}=== Validação de Sucesso ===${NC}"
echo -e "${GREEN}Hora atual do sistema:${NC} $(date)"
echo -e "${GREEN}Status do Hardware Clock:${NC} $(hwclock --show)"
echo -e "\n${GREEN}Sincronização do Chrony:${NC}"
chronyc tracking | grep -E "Reference ID|Leap status"

echo -e "\n${YELLOW}Procedimento concluído! Verifique no Zabbix se o alerta foi normalizado.${NC}"