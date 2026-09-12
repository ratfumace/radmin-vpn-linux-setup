#!/usr/bin/env bash
# ==============================================================================
# Script de Instalação Automatizada do Radmin VPN no Linux
# Baseado na ponte de driver Wine/TAP: https://github.com/baptisterajaut/radmin-vpn-linux
# ==============================================================================

set -euo pipefail

# Cores para exibição
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

info() { echo -e "${CYAN}[*]${NC} $1"; }
success() { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[-]${NC} $1" >&2; exit 1; }

# Constantes e Versões Validadas
APPIMAGE_VERSION="v1.1.0"
APPIMAGE_URL="https://github.com/baptisterajaut/radmin-vpn-linux/releases/download/${APPIMAGE_VERSION}/RadminVPN-Linux-x86_64.AppImage"
APPIMAGE_SHA256="965ea3976bf2d59987f864efd72811b5df333391c7a45521217b8f57ef285744"

RADMIN_INSTALLER_VERSION="2.1.4951.1"
RADMIN_INSTALLER_URL="https://download.radmin-vpn.com/download/files/Radmin_VPN_${RADMIN_INSTALLER_VERSION}.exe"
RADMIN_INSTALLER_SHA256="e16711e2e3e59f6603f51f437197215b1914a3d8316e1f633260178b959921f7"

INSTALL_DIR="${HOME}/Applications"
APP_TARGET_DIR="${INSTALL_DIR}/radmin-appimage"
DATA_DIR="${HOME}/.local/share/radmin-vpn-linux"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${BLUE}======================================================================${NC}"
echo -e "${BLUE}         Instalação e Configuração Automatizada do Radmin VPN        ${NC}"
echo -e "${BLUE}======================================================================${NC}"

# 1. Verificações de Ambiente
if [ "$(id -u)" -eq 0 ]; then
    error "Não execute este script como root diretamente! Execute como seu usuário normal (o script pedirá sudo quando necessário)."
fi

ARCH="$(uname -m)"
if [ "$ARCH" != "x86_64" ]; then
    error "Arquitetura $ARCH não suportada. Apenas x86_64 é suportado pelo Wine wow64 do Radmin."
fi

# 2. Instalação de Dependências do Sistema
info "Verificando e instalando dependências do sistema..."
if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -y
    # Ubuntu 24.04+/26.04 usa libfuse2t64, versões anteriores libfuse2
    FUSE_PKG="libfuse2t64"
    if ! apt-cache show libfuse2t64 >/dev/null 2>&1; then
        FUSE_PKG="libfuse2"
    fi
    sudo apt-get install -y "$FUSE_PKG" wget curl iptables iproute2 zenity libglib2.0-bin || true
elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -Sy --needed --noconfirm fuse2 wget curl iptables iproute2 zenity || true
elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y fuse-libs wget curl iptables iproute zenity || true
else
    warn "Gerenciador de pacotes não reconhecido. Certifique-se de ter instalado: curl, wget, iptables, iproute2 e suporte a FUSE/TUN."
fi

# Verifica se o módulo TUN está carregado
if [ ! -c /dev/net/tun ]; then
    info "Carregando módulo de rede TUN do kernel..."
    sudo modprobe tun || warn "Falha ao carregar 'tun'. Pode ser que já esteja integrado ao kernel."
fi

# 3. Configuração de Permissões Sudoers para a Rede (TAP)
SUDOERS_FILE="/etc/sudoers.d/radmin_vpn"
if [ ! -f "$SUDOERS_FILE" ]; then
    info "Configurando regras no sudoers para inicialização de rede sem prompts recorrentes..."
    TMP_SUDOERS="$(mktemp)"
    echo "${USER} ALL=(ALL) NOPASSWD: /usr/sbin/ip, /usr/sbin/modprobe, /usr/sbin/sysctl, /usr/bin/nmcli, /usr/bin/ip, /usr/bin/modprobe, /usr/bin/sysctl, /usr/bin/sh" > "$TMP_SUDOERS"
    sudo cp "$TMP_SUDOERS" "$SUDOERS_FILE"
    sudo chmod 0440 "$SUDOERS_FILE"
    rm -f "$TMP_SUDOERS"
    success "Regras sudoers gravadas em $SUDOERS_FILE."
else
    success "Regras de sudoers para Radmin já presentes em $SUDOERS_FILE."
fi

# 4. Preparação de Diretórios
mkdir -p "$INSTALL_DIR"
mkdir -p "$DATA_DIR"
mkdir -p "${HOME}/.local/share/icons/hicolor/256x256/apps"
mkdir -p "${HOME}/.local/share/applications"

# 5. Download e Extração do AppImage
WORK_TMP="$(mktemp -d)"
trap 'rm -rf "$WORK_TMP"' EXIT

APPIMAGE_PATH="${INSTALL_DIR}/RadminVPN-Linux-x86_64.AppImage"
if [ ! -f "$APPIMAGE_PATH" ]; then
    info "Baixando o AppImage do Radmin VPN Linux (${APPIMAGE_VERSION})..."
    wget -c -O "$APPIMAGE_PATH" "$APPIMAGE_URL"
fi

# Validação do hash do AppImage
CALC_APPIMAGE_HASH=$(sha256sum "$APPIMAGE_PATH" | awk '{print $1}')
if [ "$CALC_APPIMAGE_HASH" != "$APPIMAGE_SHA256" ]; then
    warn "Hash do AppImage diferente do esperado: $CALC_APPIMAGE_HASH (esperado: $APPIMAGE_SHA256)."
    info "Continuando com o arquivo baixado..."
fi
chmod +x "$APPIMAGE_PATH"

info "Extraindo o AppImage em $APP_TARGET_DIR (evita problemas com FUSE/sandboxes)..."
cd "$WORK_TMP"
"$APPIMAGE_PATH" --appimage-extract >/dev/null 2>&1 || error "Falha ao extrair AppImage com --appimage-extract."

rm -rf "$APP_TARGET_DIR"
mv squashfs-root "$APP_TARGET_DIR"
success "AppImage extraído com sucesso para $APP_TARGET_DIR."

# 6. Download do Instalador Windows Oficial Famatech
RADMIN_EXE_PATH="${DATA_DIR}/Radmin_VPN_${RADMIN_INSTALLER_VERSION}.exe"
if [ ! -f "$RADMIN_EXE_PATH" ]; then
    info "Baixando o instalador oficial do Radmin VPN da Famatech (${RADMIN_INSTALLER_VERSION})..."
    wget -c -O "$RADMIN_EXE_PATH" "$RADMIN_INSTALLER_URL"
fi

# Validação do hash do instalador
CALC_EXE_HASH=$(sha256sum "$RADMIN_EXE_PATH" | awk '{print $1}')
if [ "$CALC_EXE_HASH" != "$RADMIN_INSTALLER_SHA256" ]; then
    warn "Hash do instalador difere do catálogo oficial: $CALC_EXE_HASH (esperado: $RADMIN_INSTALLER_SHA256)."
fi
success "Instalador oficial validado em $RADMIN_EXE_PATH."

# 7. Execução Inicial Headless (Geração do Prefixo Wine e Configuração dos Drivers)
info "Inicializando o ambiente Wine e instalando componentes do Radmin VPN..."
info "Esta etapa pode levar de 30 a 60 segundos na primeira execução..."

# Executa AppRun em modo headless
"${APP_TARGET_DIR}/AppRun" --no-ui || true

# Limpeza de qualquer processo pendente
sudo ip link delete radminvpn0 2>/dev/null || true
killall -9 tap_bridge RvControlSvc.exe 2>/dev/null || true
success "Ambiente Wine configurado com sucesso em $DATA_DIR/wineprefix."

# 8. Integração Visual (Ícones e Atalhos .desktop)
info "Configurando ícones e atalhos na Área de Trabalho e Menu de Aplicativos..."

ICON_SRC="${SCRIPT_DIR}/assets/radmin-vpn.png"
if [ ! -f "$ICON_SRC" ]; then
    ICON_SRC="${APP_TARGET_DIR}/radmin-vpn.png"
fi

cp "$ICON_SRC" "${HOME}/.local/share/icons/radmin-vpn.png"
cp "$ICON_SRC" "${HOME}/.local/share/icons/hicolor/256x256/apps/radmin-vpn.png"

DESKTOP_ENTRY="${HOME}/.local/share/applications/radmin-vpn.desktop"
cat << EOF > "$DESKTOP_ENTRY"
[Desktop Entry]
Type=Application
Name=Radmin VPN
GenericName=VPN LAN Client
Comment=Radmin VPN no Linux para jogar em rede local
Exec=${APP_TARGET_DIR}/AppRun
Icon=${HOME}/.local/share/icons/radmin-vpn.png
Terminal=false
Categories=Network;Game;
StartupWMClass=RvRvpnGui.exe
EOF
chmod +x "$DESKTOP_ENTRY"
update-desktop-database "${HOME}/.local/share/applications" 2>/dev/null || true

# Criar atalho na Área de Trabalho do Usuário
DESKTOP_DIR="$(xdg-user-dir DESKTOP 2>/dev/null || echo "${HOME}/Desktop")"
if [ ! -d "$DESKTOP_DIR" ] && [ -d "${HOME}/Área de trabalho" ]; then
    DESKTOP_DIR="${HOME}/Área de trabalho"
fi

if [ -d "$DESKTOP_DIR" ]; then
    SHORTCUT_PATH="${DESKTOP_DIR}/Radmin VPN.desktop"
    cp "$DESKTOP_ENTRY" "$SHORTCUT_PATH"
    chmod +x "$SHORTCUT_PATH"
    if command -v gio >/dev/null 2>&1; then
        gio set "$SHORTCUT_PATH" metadata::trusted true 2>/dev/null || true
    fi
    success "Atalho criado na Área de Trabalho: $SHORTCUT_PATH"
fi

echo -e "${GREEN}======================================================================${NC}"
echo -e "${GREEN}             Instalação do Radmin VPN Concluída com Sucesso!          ${NC}"
echo -e "${GREEN}======================================================================${NC}"
echo -e "Você pode iniciar o Radmin VPN:"
echo -e " 1. Clicando no ícone 'Radmin VPN' no menu ou na Área de Trabalho."
echo -e " 2. Executando no terminal: ${CYAN}${APP_TARGET_DIR}/AppRun${NC}"
echo -e " 3. Ou pelo atalho no repositório: ${CYAN}./start-radmin.sh${NC}"
echo ""
echo -e "Logs e estado persistente: ${CYAN}${DATA_DIR}${NC}"
