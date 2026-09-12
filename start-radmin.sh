#!/usr/bin/env bash
# ==============================================================================
# Inicializador do Radmin VPN via Terminal
# ==============================================================================

set -euo pipefail

APPRUN="${HOME}/Applications/radmin-appimage/AppRun"

if [ ! -f "$APPRUN" ]; then
    echo -e "\033[0;31m[-] Radmin VPN não encontrado em $APPRUN.\033[0m"
    echo -e "Execute primeiro o instalador: ./install.sh"
    exit 1
fi

exec "$APPRUN" "$@"
