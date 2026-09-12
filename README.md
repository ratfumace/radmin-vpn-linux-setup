# Radmin VPN no Linux (Guia Completo & Setup Automatizado)

Repositório com a documentação completa, scripts de automação e arquivos necessários para instalar, configurar e rodar o **Radmin VPN** no Linux nativamente via Wine e dispositivo virtual TAP.

Este método permite conectar-se a redes do Radmin VPN criadas no Windows, jogar jogos em LAN com amigos e acessar servidores sem a necessidade de uma máquina virtual pesada.

---

## Índice

1. [Como Funciona a Solução (Arquitetura)](#como-funciona-a-solução-arquitetura)
2. [Documentação do Método Utilizado Nesta Máquina](#documentação-do-método-utilizado-nesta-máquina)
3. [Instalação Rápida Automatizada (Reprodutível)](#instalação-rápida-automatizada-reprodutível)
4. [Instalação Manual Passo a Passo](#instalação-manual-passo-a-passo)
5. [Estrutura de Arquivos e Persistência](#estrutura-de-arquivos-e-persistência)
6. [Dicas Importantes de Uso](#dicas-importantes-de-uso)
7. [Solução de Problemas (Troubleshooting)](#solução-de-problemas-troubleshooting)
8. [Desinstalação](#desinstalação)

---

## Como Funciona a Solução (Arquitetura)

O **Radmin VPN** oficial da Famatech é um software exclusivo para Windows que depende de um driver de rede NDIS (`rvpnnetmp.sys`) para criar seu adaptador virtual. O Wine tradicional não oferece suporte a drivers NDIS do Windows, o que sempre impediu o Radmin de funcionar no Linux.

A solução utilizada (baseada no projeto [radmin-vpn-linux](https://github.com/baptisterajaut/radmin-vpn-linux)) resolve essa limitação por meio de uma engenharia de pontes (bridge):

```
                   +--------------------------------------------+
                   |               Wine Runtime                 |
                   |                                            |
                   |  [Radmin GUI]       [RvControlSvc.exe]     |
                   |         |                    |             |
                   |         +---------+----------+             |
                   |                   |                        |
                   |       [adapter_hook.dll] (Hook Wine)       |
                   |                   |                        |
                   |       [rvpnnetmp.sys] (Driver Shim)        |
                   +-------------------|------------------------+
                                       | (FIFO / IPC)
                   +-------------------|------------------------+
                   |            Host Linux                      |
                   |                   v                        |
                   |             [tap_bridge]                   |
                   |                   |                        |
                   |                   v                        |
                   |        Interface TAP: radminvpn0           |
                   |        Sub-rede: 26.0.0.0/8                |
                   |                   |                        |
                   |                   v                        |
                   |    Seus Jogos / Conexões de Rede LAN       |
                   +--------------------------------------------+
```

### Componentes Principais:
- **`adapter_hook.dll`**: Intercepta chamadas de sistema no Wine simulando o comportamento do registro do Windows e dos identificadores de placa de rede (GUID e MAC).
- **`rvpnnetmp.sys`**: Driver substituto sob o Wine que recebe os pacotes de rede e os encaminha através de pipes nomeados (FIFOs).
- **`tap_bridge`**: Daemon nativo compilado para Linux que escuta os pacotes do driver e os injeta na interface de rede virtual do Linux (`radminvpn0`).
- **`AppImage` / Wine Staging WoW64**: Runtime embutido do Wine da Kron4ek (Wine 11.x) que executa binários de 32 e 64 bits sem conflitar com o Wine do sistema operacional.

---

## Documentação do Método Utilizado Nesta Máquina

A instalação existente na máquina foi configurada em **01/09/2026** utilizando o pacote AppImage pré-compilado v1.1.0 com extração direta para evitar problemas de compatibilidade com o subsistema FUSE e AppArmor nas versões modernas do Ubuntu.

### Histórico exato dos passos executados:

1. **Instalação das dependências de rede e sistema:**
   ```bash
   sudo apt update
   sudo apt install -y libfuse2t64 wget curl iptables iproute2
   ```

2. **Download do AppImage do Radmin VPN Linux (v1.1.0):**
   ```bash
   mkdir -p ~/Applications
   cd ~/Applications
   wget -O RadminVPN-Linux-x86_64.AppImage \
     https://github.com/baptisterajaut/radmin-vpn-linux/releases/download/v1.1.0/RadminVPN-Linux-x86_64.AppImage
   chmod +x RadminVPN-Linux-x86_64.AppImage
   ```

3. **Extração do AppImage para `~/Applications/radmin-appimage`:**
   > **Por que extrair?** Nas distribuições Linux recentes (Ubuntu 24.04, 26.04, etc.), a montagem de AppImages via FUSE pode falhar devido a restrições de *user namespaces* e do AppArmor. Extrair o AppImage elimina 100% dos erros de FUSE e permite que o `AppRun` acesse os binários diretamente.
   ```bash
   cd ~/Applications
   ./RadminVPN-Linux-x86_64.AppImage --appimage-extract
   mv squashfs-root radmin-appimage
   ```

4. **Configuração de regras sem senha no sudoers (`/etc/sudoers.d/radmin_vpn`):**
   O Radmin VPN precisa de privilégios de root para criar a interface TAP `radminvpn0` e adicionar as rotas de rede da faixa `26.0.0.0/8`. Para não pedir senha repetidamente via terminal ou janela gráfica a cada inicialização:
   ```bash
   echo "igris ALL=(ALL) NOPASSWD: /usr/sbin/ip, /usr/sbin/modprobe, /usr/sbin/sysctl, /usr/bin/nmcli, /usr/bin/ip, /usr/bin/modprobe, /usr/bin/sysctl, /usr/bin/sh" | sudo tee /etc/sudoers.d/radmin_vpn
   sudo chmod 0440 /etc/sudoers.d/radmin_vpn
   ```

5. **Download e alocação do instalador Windows oficial Famatech:**
   A versão validada para compatibilidade perfeita com a ponte é a **2.1.4951.1**:
   ```bash
   mkdir -p ~/.local/share/radmin-vpn-linux
   wget -c -O ~/.local/share/radmin-vpn-linux/Radmin_VPN_2.1.4951.1.exe \
     https://download.radmin-vpn.com/download/files/Radmin_VPN_2.1.4951.1.exe
   ```

6. **Inicialização headless do Wineprefix e setup dos serviços:**
   ```bash
   ~/Applications/radmin-appimage/AppRun --no-ui
   ```

7. **Criação do atalho e ícone no sistema:**
   - O ícone foi colocado em `~/.local/share/icons/radmin-vpn.png`.
   - O lançador `.desktop` foi gravado em `~/.local/share/applications/radmin-vpn.desktop` e copiado para a Área de Trabalho (`~/Área de trabalho/Radmin VPN.desktop`).
   - Foi executado `gio set "~/Área de trabalho/Radmin VPN.desktop" metadata::trusted true` para permitir a execução gráfica imediata com clique duplo no KDE/GNOME.

---

## Instalação Rápida Automatizada (Reprodutível)

Para repetir a instalação do zero em qualquer computador Linux:

1. Clone este repositório:
   ```bash
   git clone <URL_DO_REPOSITORIO> radmin-vpn-linux-setup
   cd radmin-vpn-linux-setup
   ```

2. Execute o script de instalação:
   ```bash
   chmod +x install.sh
   ./install.sh
   ```

O script irá:
- Detectar a distribuição (Ubuntu, Debian, Fedora, Arch) e instalar dependências (`wget`, `curl`, `iptables`, `iproute2`, `libfuse2`).
- Baixar o AppImage validado e conferir o hash SHA-256.
- Extrair os arquivos para `~/Applications/radmin-appimage`.
- Baixar o instalador oficial da Famatech (`Radmin_VPN_2.1.4951.1.exe`) e conferir o hash.
- Configurar o `/etc/sudoers.d/radmin_vpn` de forma segura.
- Realizar a primeira inicialização headless para montar o Wineprefix.
- Instalar os ícones e criar os atalhos no menu e na sua Área de Trabalho.

---

## Instalação Manual Passo a Passo

Caso queira executar os passos individualmente sem usar o script automático, siga a ordem:

### 1. Pré-requisitos do Sistema
```bash
# Ubuntu / Debian
sudo apt update && sudo apt install -y libfuse2t64 wget curl iptables iproute2 zenity

# Arch Linux
sudo pacman -Sy --needed fuse2 wget curl iptables iproute2 zenity

# Fedora
sudo dnf install -y fuse-libs wget curl iptables iproute zenity
```

### 2. Baixar e Extrair o AppImage
```bash
mkdir -p ~/Applications
cd ~/Applications
wget -O RadminVPN-Linux-x86_64.AppImage https://github.com/baptisterajaut/radmin-vpn-linux/releases/download/v1.1.0/RadminVPN-Linux-x86_64.AppImage
chmod +x RadminVPN-Linux-x86_64.AppImage
./RadminVPN-Linux-x86_64.AppImage --appimage-extract
rm -rf radmin-appimage
mv squashfs-root radmin-appimage
```

### 3. Baixar o Instalador Oficial Famatech
```bash
mkdir -p ~/.local/share/radmin-vpn-linux
wget -O ~/.local/share/radmin-vpn-linux/Radmin_VPN_2.1.4951.1.exe \
  https://download.radmin-vpn.com/download/files/Radmin_VPN_2.1.4951.1.exe
```

### 4. Permissões de Rede Sudoers
```bash
echo "${USER} ALL=(ALL) NOPASSWD: /usr/sbin/ip, /usr/sbin/modprobe, /usr/sbin/sysctl, /usr/bin/nmcli, /usr/bin/ip, /usr/bin/modprobe, /usr/bin/sysctl, /usr/bin/sh" | sudo tee /etc/sudoers.d/radmin_vpn
sudo chmod 0440 /etc/sudoers.d/radmin_vpn
```

### 5. Primeira Execução Headless
```bash
~/Applications/radmin-appimage/AppRun --no-ui
```

### 6. Atalho na Área de Trabalho e Menu
```bash
cp assets/radmin-vpn.png ~/.local/share/icons/radmin-vpn.png

cat << 'EOF' > ~/.local/share/applications/radmin-vpn.desktop
[Desktop Entry]
Type=Application
Name=Radmin VPN
GenericName=VPN LAN Client
Comment=Radmin VPN no Linux para jogar em rede local
Exec=/home/USER/Applications/radmin-appimage/AppRun
Icon=/home/USER/.local/share/icons/radmin-vpn.png
Terminal=false
Categories=Network;Game;
StartupWMClass=RvRvpnGui.exe
EOF

# Substitua /home/USER pelo caminho real do seu $HOME
sed -i "s|/home/USER|$HOME|g" ~/.local/share/applications/radmin-vpn.desktop

# Copie para a Área de trabalho
DESK_DIR="$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")"
[ -d "$HOME/Área de trabalho" ] && DESK_DIR="$HOME/Área de trabalho"
cp ~/.local/share/applications/radmin-vpn.desktop "$DESK_DIR/Radmin VPN.desktop"
chmod +x "$DESK_DIR/Radmin VPN.desktop"
gio set "$DESK_DIR/Radmin VPN.desktop" metadata::trusted true 2>/dev/null || true
```

---

## Estrutura de Arquivos e Persistência

| Caminho | Descrição |
|---|---|
| `~/Applications/radmin-appimage/` | Diretório raiz extraído do AppImage contendo o Wine embutido e os binários da ponte (`tap_bridge`). |
| `~/Applications/radmin-appimage/AppRun` | Executável principal de lançamento do aplicativo. |
| `~/.local/share/radmin-vpn-linux/` | Diretório de dados persistentes do usuário. |
| `~/.local/share/radmin-vpn-linux/wineprefix/` | Prefixo do Wine onde o Radmin VPN Windows está instalado. Seu ID (RID), configurações de rede e certificados ficam gravados aqui. |
| `~/.local/share/radmin-vpn-linux/run.log` | Arquivo com o histórico de logs da última execução. |
| `/etc/sudoers.d/radmin_vpn` | Regras de sudo para permitir manipulação da interface de rede `radminvpn0`. |
| `~/.local/share/applications/radmin-vpn.desktop` | Lançador no menu de aplicativos. |

---

## Dicas Importantes de Uso

### ⚠️ Desative a Atualização Automática no Radmin
O instalador padrão do Radmin VPN possui um atualizador automático que tenta baixar versões mais recentes do Windows em segundo plano. Sob o Wine, essa atualização em tempo de execução pode fechar a janela ou travar o serviço.

**Como desativar:**
1. Abra o Radmin VPN.
2. Acesse **Sistema (System)** -> **Opções (Options)**.
3. Na guia de atualizações, **desmarque** a opção de atualização automática.

### Atualizando o Radmin Controladamente
Caso queira atualizar o Radmin sem perder seu prefixo e o seu identificador de rede (RID), use o parâmetro de atualização:
```bash
~/Applications/radmin-appimage/AppRun --update
```

---

## Solução de Problemas (Troubleshooting)

### 1. Interface `radminvpn0` ficou travada ou erro "Device or resource busy"
Se o programa fechou de forma forçada e a interface de rede permaneceu ativa:
```bash
sudo ip link delete radminvpn0 2>/dev/null || true
killall -9 RvControlSvc.exe RvRvpnGui.exe tap_bridge 2>/dev/null || true
```

### 2. Pedindo senha de sudo repetidamente na inicialização
Verifique se as permissões do sudoers foram aplicadas corretamente:
```bash
sudo -n true
```
Se retornar erro, reconfigure o arquivo `/etc/sudoers.d/radmin_vpn` conforme indicado na seção de instalação.

### 3. A janela não abre ou fecha imediatamente
Verifique o log de execução:
```bash
cat ~/.local/share/radmin-vpn-linux/run.log
```
Geralmente o log indica se houve conflito com o servidor X/Wayland ou erro de montagem da interface TAP.

---

## Desinstalação

Para remover o Radmin VPN e todos os atalhos:

```bash
./uninstall.sh
```

Para remover também todos os dados persistentes (Wineprefix, histórico de redes e seu IP registrado):
```bash
./uninstall.sh --purge
```
