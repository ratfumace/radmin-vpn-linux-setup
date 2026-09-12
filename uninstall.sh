#!/usr/bin/env bash
# ==============================================================================
# Script de Desinstalação e Limpeza do Radmin VPN no Linux
# ==============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info() { echo -e "${CYAN}[*]${NC} $1"; }
success() { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }

PURGE=false
if [[ "${1:-}" == "--purge" ]]; then
    PURGE=true
fi

echo -e "${YELLOW}Encerrando processos ativos do Radmin VPN...${NC}"
killall -9 RvControlSvc.exe RvRvpnGui.exe tap_bridge 2>/dev/null || true

info "Removendo interface de rede virtual TAP..."
sudo ip link delete radminvpn0 2>/dev/null || true

info "Removendo atalhos do sistema e da Área de Trabalho..."
rm -f "${HOME}/.local/share/applications/radmin-vpn.desktop"
rm -f "${HOME}/Desktop/Radmin VPN.desktop"
rm -f "${HOME}/Área de trabalho/Radmin VPN.desktop"
rm -f "${HOME}/.local/share/icons/radmin-vpn.png"
rm -f "${HOME}/.local/share/icons/hicolor/256x256/apps/radmin-vpn.png"
update-desktop-database "${HOME}/.local/share/applications" 2>/dev/null || true

info "Removendo binários e runtime em ~/Applications..."
rm -rf "${HOME}/Applications/radmin-appimage"
rm -f "${HOME}/Applications/RadminVPN-Linux-x86_64.AppImage"

if [ -f "/etc/sudoers.d/radmin_vpn" ]; then
    read -rp "Deseja remover as permissões do /etc/sudoers.d/radmin_vpn? [s/N]: " rm_sudoers || rm_sudoers="n"
    if [[ "$rm_sudoers" =~ ^[sSyY]$ ]]; then
        sudo rm -f /etc/sudoers.d/radmin_vpn
        success "Regras sudoers removidas."
    fi
fi

if [ "$PURGE" = true ]; then
    info "Removendo dados persistentes e prefixo Wine (~/.local/share/radmin-vpn-linux)..."
    rm -rf "${HOME}/.local/share/radmin-vpn-linux"
    success "Todos os dados e identificador do Radmin VPN foram purgados."
else
    info "Os dados persistentes (Wineprefix, certificados e ID do Radmin) foram mantidos em ~/.local/share/radmin-vpn-linux."
    info "Para remover tudo completamente, execute: ./uninstall.sh --purge"
fi

success "Desinstalação concluída com sucesso."
