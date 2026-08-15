#!/bin/bash
# =====================================
#  SKRYPT INSTALACYJNY - Arch Linux 
# =====================================

set -euo pipefail

detect_system_lang() {
    local sys_lang="${LANG:-}"
    [[ -z "$sys_lang" ]] && sys_lang="${LC_ALL:-${LC_MESSAGES:-}}"
    if [[ "$sys_lang" == pl_PL* || "$sys_lang" == pl* ]]; then
        echo "pl"
    else
        echo "en"
    fi
}
SCRIPT_LANG="$(detect_system_lang)"

INFO='\033[0;34m'
SUCCESS='\033[0;32m'
WARN='\033[0;33m'
ERR='\033[0;31m'
NC='\033[0m'

TMP_LOG="$(mktemp /tmp/install-log.XXXXXX)"
LOG_FILE="$HOME/install_error_$(date +%Y%m%d_%H%M%S).log"

exec 3>&1
exec >>"$TMP_LOG" 2>&1

printf '\033[?7l' >&3

cleanup_on_exit() {
    local exit_code=$?
    printf '\033[?7h' >&3
    if [ "$exit_code" -ne 0 ]; then
        echo -e "\n" >&3
        cp -f "$TMP_LOG" "$LOG_FILE" 2>/dev/null || true
        if [[ "$SCRIPT_LANG" == "pl" ]]; then
            echo -e "${ERR}✘ Wystąpił błąd (kod: $exit_code). Szczegółowy log zapisano w: $LOG_FILE${NC}" >&3
        else
            echo -e "${ERR}✘ An error occurred (code: $exit_code). Detailed log saved to: $LOG_FILE${NC}" >&3
        fi
    fi
    rm -f "$TMP_LOG"
}
trap cleanup_on_exit EXIT

_pick_msg() { [[ "$SCRIPT_LANG" == "pl" ]] && echo "$1" || echo "$2"; }
log_info()  { local m; m="$(_pick_msg "$1" "$2")"; echo -e "${INFO}==> $m${NC}"; }
log_ok()    { local m; m="$(_pick_msg "$1" "$2")"; echo -e "${SUCCESS}✔ $m${NC}"; }
log_err()   { local m; m="$(_pick_msg "$1" "$2")"; echo -e "${ERR}✘ ERROR: $m${NC}"; }
log_warn()  { local m; m="$(_pick_msg "$1" "$2")"; echo -e "${WARN}⚠ WARN: $m${NC}"; }

trap 'log_err "Błąd w linii $LINENO. Polecenie: $BASH_COMMAND" "Error at line $LINENO. Command: $BASH_COMMAND"' ERR

show_progress() {
    local step=$1
    local total=$2
    local msg=$3
    local percent=$(( step * 100 / total ))

    local cols
    cols=$(tput cols 2>/dev/null)
    [[ "$cols" =~ ^[0-9]+$ ]] || cols=80

    local bar_width=50
    local reserved=12
    if (( cols - reserved < bar_width )); then
        bar_width=$(( cols - reserved ))
        (( bar_width < 10 )) && bar_width=10
    fi

    local overhead=$(( bar_width + reserved ))
    local avail=$(( cols - overhead ))
    if (( avail < 5 )); then avail=5; fi
    if (( ${#msg} > avail )); then
        msg="${msg:0:$((avail - 1))}…"
    fi

    local filled=$(( percent * bar_width / 100 ))
    local empty=$(( bar_width - filled ))

    local bar_filled=""
    local bar_empty=""
    if [ $filled -gt 0 ]; then printf -v bar_filled '%*s' "$filled" ''; bar_filled="${bar_filled// /#}"; fi
    if [ $empty -gt 0 ]; then printf -v bar_empty '%*s' "$empty" ''; bar_empty="${bar_empty// /-}"; fi

    printf "\r\033[K[\033[1;32m%s\033[0;90m%s\033[0m] %3d%% | \033[1;36m%s\033[0m" "$bar_filled" "$bar_empty" "$percent" "$msg" >&3
}

if [[ "$SCRIPT_LANG" == "pl" ]]; then
    MSG_PHASE_1="[1/3] Konfiguracja i optymalizacja systemu..."
    MSG_PHASE_2="[2/3] Instalacja pakietów systemowych, Flatpak i AUR..."
    MSG_PHASE_3="[3/3] Konfiguracja usług, bootloadera i środowiska..."
else
    MSG_PHASE_1="[1/3] System configuration and optimization..."
    MSG_PHASE_2="[2/3] Installing system, Flatpak, and AUR packages..."
    MSG_PHASE_3="[3/3] Configuring services, bootloader, and environment..."
fi

TOTAL_STEPS=12

if [[ "$EUID" -eq 0 ]]; then
    echo -e "${ERR}✘ Nie uruchamiaj skryptu jako root. Uruchom jako zwykły użytkownik z sudo.${NC}" >&3
    exit 1
fi

# =============================================================
#  ETAP 1/3: KONFIGURACJA I OPTYMALIZACJA SYSTEMU
# =============================================================
show_progress 0 $TOTAL_STEPS "$MSG_PHASE_1"

install_pacman_pkgs() {
    local valid_pkgs=()
    for pkg in "$@"; do
        if pacman -Si "$pkg" &>/dev/null; then
            valid_pkgs+=("$pkg")
        fi
    done
    if [ ${#valid_pkgs[@]} -gt 0 ]; then
        sudo pacman -S --noconfirm --needed "${valid_pkgs[@]}"
    fi
}

install_yay_pkgs() {
    local valid_pkgs=()
    for pkg in "$@"; do
        if yay -Si "$pkg" &>/dev/null; then
            valid_pkgs+=("$pkg")
        fi
    done
    if [ ${#valid_pkgs[@]} -gt 0 ]; then
        yay -S --noconfirm --needed "${valid_pkgs[@]}"
    fi
}

CURRENT_USER=$(whoami)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GPU_TYPE="unknown"
if command -v lspci &>/dev/null; then
    if lspci | grep -i 'vga\|3d\|display' | grep -qi 'nvidia'; then
        GPU_TYPE="nvidia"
    elif lspci | grep -i 'vga\|3d\|display' | grep -qi 'amd\|radeon'; then
        GPU_TYPE="amd"
    elif lspci | grep -i 'vga\|3d\|display' | grep -qi 'intel'; then
        GPU_TYPE="intel"
    fi
fi

if [ -f "$SCRIPT_DIR/.update.sh" ]; then
    cp -af "$SCRIPT_DIR/.update.sh" ~/.update.sh
    chmod +x ~/.update.sh
fi

if [ -d "$SCRIPT_DIR/.local" ]; then
    mkdir -p ~/.local
    cp -afT "$SCRIPT_DIR/.local" ~/.local
fi

if [ -d "$SCRIPT_DIR/.config" ]; then
    mkdir -p ~/.config
    cp -afT "$SCRIPT_DIR/.config" ~/.config
fi

show_progress 1 $TOTAL_STEPS "$MSG_PHASE_1"

sudo -v
echo "$CURRENT_USER ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/99-temp-installer > /dev/null

PACKAGES_TO_REMOVE="htop nano konqueror plasma-browser-integration plasma-vault krdp krfb plasma-thunderbolt kontact kmail kontrast plasma-welcome imagemagick kaddressbook kdepim-runtime akonadi-server akregator korganizer gnome-software epiphany decibels rhythmbox showtime cosmic-store cosmic-player parole kwalletmanager"
INSTALLED_PACKAGES=$(pacman -Qq $PACKAGES_TO_REMOVE 2>/dev/null || true)
if [ -n "$INSTALLED_PACKAGES" ]; then
    sudo pacman -Rs --noconfirm $INSTALLED_PACKAGES 2>/dev/null || true
fi

mkdir -p ~/.config
if [[ -f ~/.config/kwalletrc ]]; then
    if grep -q "^\[Wallet\]" ~/.config/kwalletrc; then
        sed -i '/^\[Wallet\]/,/^\[/{s/^Enabled=.*/Enabled=false/}' ~/.config/kwalletrc
        grep -q "^Enabled=" ~/.config/kwalletrc || sed -i '/^\[Wallet\]/a Enabled=false' ~/.config/kwalletrc
    else
        printf '[Wallet]\nEnabled=false\n' >> ~/.config/kwalletrc
    fi
else
    printf '[Wallet]\nEnabled=false\n' > ~/.config/kwalletrc
fi

show_progress 2 $TOTAL_STEPS "$MSG_PHASE_1"

sudo sed -i 's/^#[[:space:]]*Color/Color/' /etc/pacman.conf
if ! grep -qw "ILoveCandy" /etc/pacman.conf; then
    sudo sed -i '/^Color/a ILoveCandy' /etc/pacman.conf
fi
sudo sed -i 's/^[[:space:]]*CheckSpace/#CheckSpace/' /etc/pacman.conf
sudo sed -i 's/^#[[:space:]]*ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
sudo sed -i 's/^ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
sudo sed -i 's/^#[[:space:]]*VerbosePkgLists/VerbosePkgLists/' /etc/pacman.conf

if ! grep -q "NoExtract = usr/share/locale" /etc/pacman.conf; then
    sudo sed -i '/^\[options\]/a NoExtract = usr/share/locale/* !usr/share/locale/pl* !usr/share/locale/en*\nNoExtract = usr/share/cups/doc/*' /etc/pacman.conf
fi
if ! grep -q "NoExtract = usr/share/man" /etc/pacman.conf; then
    sudo sed -i '/NoExtract = usr\/share\/cups\/doc/a NoExtract = usr/share/man/*\nNoExtract = usr/share/doc/*\nNoExtract = usr/share/info/*\nNoExtract = usr/share/gtk-doc/*\nNoExtract = usr/share/help/*' /etc/pacman.conf
fi
sudo pacman -S --noconfirm cups

sudo mkdir -p /etc/NetworkManager/conf.d
echo -e "[main]\ndns=default\nrc-manager=symlink" | sudo tee /etc/NetworkManager/conf.d/dns.conf > /dev/null
echo -e "[global-dns]\n\n[global-dns-domain-*]\nservers=1.1.1.1,1.0.0.1,2606:4700:4700::1112,2606:4700:4700::1002" | sudo tee /etc/NetworkManager/conf.d/global-dns.conf > /dev/null

show_progress 3 $TOTAL_STEPS "$MSG_PHASE_1"

# =============================================================
#  ETAP 2/3: INSTALACJA PAKIETÓW I OPROGRAMOWANIA
# =============================================================
show_progress 4 $TOTAL_STEPS "$MSG_PHASE_2"

sudo pacman -Syu --noconfirm

show_progress 5 $TOTAL_STEPS "$MSG_PHASE_2"

SYSTEM_PKGS=(
    base-devel git zsh pacman-contrib fastfetch reflector
    gcc make cmake meson ninja just
    python-pip python-tqdm python-defusedxml python-packaging
    gwenview okular ark
    partitionmanager bleachbit unrar mc btrfs-progs exfat-utils ntfs-3g os-prober
    fsarchiver inxi pv rsync 7zip zenity innoextract android-tools dnsmasq vde2 cdemu-client cdemu-daemon vhba-module
    plymouth profile-sync-daemon ananicy-cpp dconf-editor geoclue fwupd fwupd-efi
    bluez-obex appmenu-gtk-module libayatana-appindicator flatpak timeshift
    thunderbird thunderbird-i18n-pl zsh-syntax-highlighting zsh-autosuggestions
    vlc vlc-plugins-all libappimage handbrake
    krita krita-plugin-gmic gimp gmic
    audacity qmmp mixxx kdenlive soundconverter
    gst-plugins-good gst-plugins-bad gst-plugins-ugly
    discord telegram-desktop qbittorrent firefox-developer-edition firefox-developer-edition-i18n-pl
    libreoffice-fresh libreoffice-fresh-pl hunspell-pl
    wine-staging winetricks gamemode gamescope mangohud goverlay vkd3d
    vulkan-dzn vulkan-gfxstream vulkan-swrast
    virt-manager qemu-desktop libvirt edk2-ovmf
    lib32-mpg123 lib32-libvdpau lib32-libtheora lib32-speex
    lib32-libxrandr lib32-libxrender lib32-gamemode
    lib32-vulkan-swrast lib32-vkd3d lib32-alsa-plugins
    lib32-libpulse lib32-openal lib32-mangohud lib32-pipewire
)

case "$GPU_TYPE" in
    "nvidia") SYSTEM_PKGS+=(lib32-nvidia-utils lib32-vulkan-icd-loader) ;;
    "amd")    SYSTEM_PKGS+=(lib32-vulkan-radeon lib32-mesa lib32-vulkan-mesa-layers lib32-mesa-utils lib32-vulkan-icd-loader) ;;
    "intel")  SYSTEM_PKGS+=(lib32-libva-intel-driver lib32-vulkan-intel lib32-mesa lib32-vulkan-mesa-layers lib32-mesa-utils lib32-vulkan-icd-loader) ;;
esac

install_pacman_pkgs "${SYSTEM_PKGS[@]}"

show_progress 6 $TOTAL_STEPS "$MSG_PHASE_2"

sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
sudo flatpak update --appstream
sudo flatpak install -y flathub com.github.tchx84.Flatseal || true
sudo flatpak install -y flathub it.mijorus.gearlever || true

show_progress 7 $TOTAL_STEPS "$MSG_PHASE_2"

if ! command -v yay &>/dev/null; then
    rm -rf /tmp/yay
    git clone https://aur.archlinux.org/yay.git /tmp/yay
    (cd /tmp/yay && makepkg -si --noconfirm)
fi

yay --save --cleanafter --cleanmenu=false --diffmenu=false --editmenu=false

AUR_PKGS=(ventoy-bin lsfg-vk-bin google-chrome brave-origin-bin faugus-launcher shelly-bin dmemcg-booster needrestart makeself)
install_yay_pkgs "${AUR_PKGS[@]}"

show_progress 8 $TOTAL_STEPS "$MSG_PHASE_2"

# =============================================================
#  ETAP 3/3: KONFIGURACJA USŁUG, BOOTLOADERA I ŚRODOWISKA
# =============================================================
show_progress 9 $TOTAL_STEPS "$MSG_PHASE_3"

CMDLINE="quiet splash"
[[ $GPU_TYPE == *"nvidia"* ]] && CMDLINE="$CMDLINE nvidia_drm.modeset=1"

BOOT_METHODS_FOUND=()

if [ -f /etc/kernel/cmdline ] && \
   { grep -rlq '_uki=' /etc/mkinitcpio.d/*.preset 2>/dev/null || \
     compgen -G "/boot/EFI/Linux/*.efi" > /dev/null 2>&1; }; then
    BOOT_METHODS_FOUND+=("uki")
    if ! grep -qw "splash" /etc/kernel/cmdline; then
        sudo sed -i "s/\$/ $CMDLINE/" /etc/kernel/cmdline
        sudo sed -i 's/  */ /g'       /etc/kernel/cmdline
    fi
fi

if command -v bootctl &>/dev/null && \
   { [ -f /boot/loader/loader.conf ] || [ -f /efi/loader/loader.conf ]; }; then
    BOOT_METHODS_FOUND+=("systemd-boot")
    for loader_root in "/boot" "/efi"; do
        if [ -d "$loader_root/loader/entries" ]; then
            [ -f "$loader_root/loader/loader.conf" ] && \
                sudo sed -i 's/^timeout .*/timeout 0/' "$loader_root/loader/loader.conf"

            for entry in "$loader_root/loader/entries/"*.conf; do
                [ -f "$entry" ] || continue
                if ! grep -qw "splash" "$entry"; then
                    sudo sed -i "/^options/ s/\$/ $CMDLINE/" "$entry"
                    sudo sed -i 's/  */ /g' "$entry"
                fi
            done
        fi
    done
fi

if [ -f /etc/default/grub ] && command -v grub-mkconfig &>/dev/null; then
    BOOT_METHODS_FOUND+=("grub")
    sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub
    sudo sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$CMDLINE\"|" \
        /etc/default/grub
    sudo grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null || \
    sudo grub-mkconfig -o /boot/GRUB/grub.cfg 2>/dev/null || true
fi

show_progress 10 $TOTAL_STEPS "$MSG_PHASE_3"

sudo plymouth-set-default-theme -R bgrt 2>/dev/null || true

if [[ $GPU_TYPE == *"nvidia"* ]]; then
    sudo sed -i 's/^MODULES=(/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm /' /etc/mkinitcpio.conf
elif [[ $GPU_TYPE == *"amd"* ]]; then
    sudo sed -i 's/^MODULES=(/MODULES=(amdgpu /' /etc/mkinitcpio.conf
elif [[ $GPU_TYPE == *"intel"* ]]; then
    sudo sed -i 's/^MODULES=(/MODULES=(i915 /' /etc/mkinitcpio.conf
fi

sudo sed -i 's/^#Theme=.*/Theme=bgrt/'       /etc/plymouth/plymouthd.conf 2>/dev/null || true
sudo sed -i 's/^#ShowDelay=.*/ShowDelay=0/'  /etc/plymouth/plymouthd.conf 2>/dev/null || true

for preset in /etc/mkinitcpio.d/*.preset; do
    [ -f "$preset" ] && sudo sed -i 's/--splash [^ "]*//g' "$preset"
done

if ! grep -q "plymouth" /etc/mkinitcpio.conf; then
    sudo sed -i 's/udev/udev plymouth/' /etc/mkinitcpio.conf
fi

sudo mkinitcpio -P

show_progress 11 $TOTAL_STEPS "$MSG_PHASE_3"

if [ -f /etc/default/ufw ]; then
    sudo sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
fi

if command -v ufw &>/dev/null; then
    sudo systemctl enable --now ufw || true
    sudo ufw allow in  on virbr0 || true
    sudo ufw allow out on virbr0 || true
fi

sudo systemctl enable --now geoclue.service || true
sudo systemctl enable --now ananicy-cpp || true
sudo systemctl enable --now fstrim.timer || true
sudo systemctl enable --now bluetooth || true
echo "options btusb enable_autosuspend=0" | sudo tee /etc/modprobe.d/btusb.conf
sudo systemctl enable --now libvirtd || true

if ! sudo virsh net-info default &>/dev/null; then
    sudo virsh net-define /usr/share/libvirt/networks/default.xml || true
fi

sudo virsh net-start default 2>/dev/null || true
sudo virsh net-autostart default || true

sudo sed -i 's/^#\?[[:space:]]*DefaultTimeoutStopSec=.*/DefaultTimeoutStopSec=3s/' /etc/systemd/system.conf
sudo sed -i 's/^#\?[[:space:]]*DefaultTimeoutStartSec=.*/DefaultTimeoutStartSec=3s/' /etc/systemd/system.conf
sudo systemctl disable NetworkManager-wait-online.service || true
sudo journalctl --vacuum-time=2d || true

if [ -d "$SCRIPT_DIR/bleachbit" ]; then
    sudo mkdir -p /root/.config/bleachbit
    sudo cp -af "$SCRIPT_DIR/bleachbit/." /root/.config/bleachbit/
fi

sudo usermod -aG libvirt,kvm "$CURRENT_USER"

if command -v zsh &>/dev/null; then
    sudo chsh -s /usr/bin/zsh "$CURRENT_USER"

    [ ! -d "$HOME/.oh-my-zsh" ] && \
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
        "" --unattended || true

    P10K_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
    [ ! -d "$P10K_DIR" ] && \
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR" || true

    if [ -f ~/.zshrc ]; then
        sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="powerlevel10k\/powerlevel10k"/' ~/.zshrc
        sed -i 's/^plugins=(.*/plugins=(git sudo systemd archlinux)/' ~/.zshrc

        if ! grep -q "LC_ALL=pl_PL.UTF-8" ~/.zshrc; then
            {
                echo ""
                echo "export LC_ALL=pl_PL.UTF-8"
                echo "export LC_MESSAGES=pl_PL.UTF-8"
                echo "fastfetch"
            } >> ~/.zshrc
        fi

        if ! grep -q "zsh-syntax-highlighting.zsh" ~/.zshrc; then
            {
                echo ""
                echo "source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
                echo "source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh"
            } >> ~/.zshrc
        fi
    fi
fi

sudo rm -f /etc/sudoers.d/99-temp-installer

show_progress 12 $TOTAL_STEPS "$MSG_PHASE_3"
echo -e "\n" >&3

if [[ "$SCRIPT_LANG" == "pl" ]]; then
    echo -e "${SUCCESS}✔ KONFIGURACJA ZAKOŃCZONA SUKCESEM!${NC}" >&3
else
    echo -e "${SUCCESS}✔ CONFIGURATION COMPLETED SUCCESSFULLY!${NC}" >&3
fi

# =============================================================
#  RESTART SYSTEMU
# =============================================================
if [[ "$SCRIPT_LANG" == "pl" ]]; then
    RESTART_PROMPT="Czy chcesz teraz zrestartować system? [Y/N]: "
else
    RESTART_PROMPT="Do you want to restart the system now? [Y/N]: "
fi
echo -en "${INFO}==> ${RESTART_PROMPT}${NC}" >&3
read -r RESTART_CHOICE < /dev/tty
case "$RESTART_CHOICE" in
    [Yy]*)
        systemctl reboot
        ;;
    *)
        exit 0
        ;;
esac