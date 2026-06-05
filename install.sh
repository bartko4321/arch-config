#!/bin/bash
# =============================================================
#  SKRYPT INSTALACYJNY - Arch Linux
# =============================================================

set -euo pipefail

# ── Kolory ────────────────────────────────────────────────────
INFO='\033[0;34m'
SUCCESS='\033[0;32m'
WARN='\033[0;33m'
NC='\033[0m'

# ── Pomocnicze funkcje logowania ──────────────────────────────
log_info()    { echo -e "${INFO}==> $1${NC}"; }
log_ok()      { echo -e "${SUCCESS}✔ $1${NC}"; }
log_warn()    { echo -e "${WARN}⚠ $1${NC}"; }

# Upewnij się, że skrypt NIE jest uruchamiany jako root
if [[ "$EUID" -eq 0 ]]; then
    log_warn "BŁĄD: Nie uruchamiaj skryptu jako root. Uruchom jako zwykły użytkownik z sudo." >&2
    exit 1
fi

# ── Funkcje filtrujące pakiety przed instalacją ───────────────
install_pacman_pkgs() {
    local valid_pkgs=()
    for pkg in "$@"; do
        if pacman -Si "$pkg" &>/dev/null; then
            valid_pkgs+=("$pkg")
        else
            log_warn "Pomijam pakiet (nie znaleziono w oficjalnych repozytoriach): $pkg"
        fi
    done

    if [ ${#valid_pkgs[@]} -gt 0 ]; then
        sudo pacman -S --noconfirm --needed "${valid_pkgs[@]}"
    else
        log_warn "Brak prawidłowych pakietów do zainstalowania z podanej listy."
    fi
}

install_yay_pkgs() {
    local valid_pkgs=()
    for pkg in "$@"; do
        if yay -Si "$pkg" &>/dev/null; then
            valid_pkgs+=("$pkg")
        else
            log_warn "Pomijam pakiet z AUR (nie znaleziono): $pkg"
        fi
    done

    if [ ${#valid_pkgs[@]} -gt 0 ]; then
        yay -S --noconfirm --needed "${valid_pkgs[@]}"
    else
        log_warn "Brak prawidłowych pakietów AUR do zainstalowania z podanej listy."
    fi
}

# ── Zmienne środowiskowe i systemowe ──────────────────────────
CURRENT_USER=$(whoami)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Wykrywanie układu graficznego (wymagane dla Bootloadera i Plymouth)
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

# =============================================================
#  1. PLIKI DODATKOWE
# =============================================================
if [ -f .update.sh ]; then
    cp -af .update.sh ~/.update.sh
    chmod +x ~/.update.sh
fi

if [ -f "$SCRIPT_DIR/Konserwacja systemu.desktop" ]; then
    mkdir -p ~/.local/share/applications/
    cp -af "$SCRIPT_DIR/Konserwacja systemu.desktop" ~/.local/share/applications/
    chmod +x ~/.local/share/applications/"Konserwacja systemu.desktop"
    log_ok "Skopiowano 'Konserwacja systemu.desktop'"
else
    log_warn "Brak pliku 'Konserwacja systemu.desktop' w katalogu skryptu – pominięto"
fi


# =============================================================
#  2. KONFIGURACJA WI-FI
# =============================================================
log_info "Konfiguracja Wi-Fi"
read -rp "Podaj SSID (nazwę sieci, Enter by pominąć): " wifi_ssid
if [ -n "$wifi_ssid" ]; then
    read -rsp "Podaj hasło: " wifi_pass
    echo ""
    nmcli dev wifi connect "$wifi_ssid" password "$wifi_pass" || log_warn "Nie udało się połączyć z Wi-Fi."
fi


# =============================================================
#  3. KONFIGURACJA SYSTEMOWA (wymaga sudo)
# =============================================================
log_info "Rozpoczynanie konfiguracji systemowej"

# ── Tymczasowy wyjątek sudo dla pacmana ───────────────────────
sudo -v
echo "$CURRENT_USER ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/99-temp-installer > /dev/null

# ── Usuwanie niechcianych pakietów ────────────────────────────
PACKAGES_TO_REMOVE="htop nano plasma-browser-integration plasma-vault konqueror krdp plasma-thunderbolt gnome-software epiphany decibels rhythmbox showtime cosmic-store cosmic-player parole"

INSTALLED_PACKAGES=$(pacman -Qq $PACKAGES_TO_REMOVE 2>/dev/null || true)

if [ -n "$INSTALLED_PACKAGES" ]; then
    # shellcheck disable=SC2086
    sudo pacman -Rs --noconfirm $INSTALLED_PACKAGES 2>/dev/null || true
fi

# ── Optymalizacja pacmana ─────────────────────────────────────
log_info "Optymalizacja /etc/pacman.conf..."

sudo sed -i 's/^#[[:space:]]*Color/Color/' /etc/pacman.conf
if ! grep -qw "ILoveCandy" /etc/pacman.conf; then
    sudo sed -i '/^Color/a ILoveCandy' /etc/pacman.conf
fi
sudo sed -i 's/^[[:space:]]*CheckSpace/#CheckSpace/' /etc/pacman.conf
sudo sed -i 's/^#[[:space:]]*ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
sudo sed -i 's/^ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
sudo sed -i 's/^#[[:space:]]*VerbosePkgLists/VerbosePkgLists/' /etc/pacman.conf

# Blokowanie wypakowywania wszystkich języków z wyjątkiem PL i EN oraz dokumentacji CUPS
log_info "Dodawanie reguł NoExtract (języki i dokumentacja CUPS)..."
if ! grep -q "NoExtract = usr/share/locale" /etc/pacman.conf; then
    sudo sed -i '/^\[options\]/a NoExtract = usr/share/locale/* !usr/share/locale/pl* !usr/share/locale/en*\nNoExtract = usr/share/cups/doc/*' /etc/pacman.conf
fi

# Blokowanie wypakowywania dokumentacji i stron podręcznika
log_info "Dodawanie reguł NoExtract (dokumentacja i man pages)..."
if ! grep -q "NoExtract = usr/share/man" /etc/pacman.conf; then
    sudo sed -i '/NoExtract = usr\/share\/cups\/doc/a NoExtract = usr/share/man/*\nNoExtract = usr/share/doc/*\nNoExtract = usr/share/info/*\nNoExtract = usr/share/gtk-doc/*\nNoExtract = usr/share/help/*' /etc/pacman.conf
fi

# Przeinstalowanie pakietu cups, aby zastosować reguły i wyczyścić stare pliki
log_info "Instalacja/Przeinstalowanie CUPS..."
sudo pacman -S --noconfirm cups

# ── DNS Cloudflare ────────────────────────────────────────────
log_info "Ustawianie DNS Cloudflare"
CONNECTION_NAME=$(nmcli -t -f NAME connection show --active 2>/dev/null | head -n 1 || true)
if [ -n "$CONNECTION_NAME" ]; then
    sudo nmcli connection modify "$CONNECTION_NAME" ipv4.dns "1.1.1.1 1.0.0.1"
    sudo nmcli connection modify "$CONNECTION_NAME" ipv4.ignore-auto-dns yes
    sudo nmcli connection modify "$CONNECTION_NAME" ipv6.dns "2606:4700:4700::1112 2606:4700:4700::1002"
    sudo nmcli connection modify "$CONNECTION_NAME" ipv6.ignore-auto-dns yes
    sudo nmcli connection up "$CONNECTION_NAME" || true
fi


# =============================================================
#  4. INSTALACJA PAKIETÓW OFICJALNYCH I FLATHUB
# =============================================================
log_info "Instalacja pakietów systemowych"
sudo pacman -Sy --noconfirm

SYSTEM_PKGS=(
    # Podstawa i narzędzia deweloperskie
    base-devel git zsh pacman-contrib btop fastfetch reflector
    gcc make cmake meson ninja just
    python-pip python-tqdm python-defusedxml python-packaging

    # Zarządzanie systemem i dyskami
    partitionmanager bleachbit unrar mc btrfs-progs exfat-utils ntfs-3g os-prober
    fsarchiver inxi pv rsync 7zip zenity innoextract android-tools dnsmasq vde2

    # Pakiety Flatpak
    flatpak

    # Multimedia i grafika
    vlc vlc-plugins-all libappimage
    gimp krita gmic qmmp
    audacity mixxx kdenlive
    gst-plugins-good gst-plugins-bad gst-plugins-ugly

    # Komunikatory i P2P
    discord telegram-desktop qbittorrent

    # Biuro
    libreoffice-fresh libreoffice-fresh-pl hunspell-pl

    # WINE i Gaming
    wine-staging winetricks gamemode gamescope mangohud goverlay vkd3d
    vulkan-dzn vulkan-gfxstream vulkan-swrast

    # Narzędzia wizualne i systemowe
    plymouth profile-sync-daemon ananicy-cpp dconf-editor geoclue fwupd fwupd-efi
    bluez-obex appmenu-gtk-module

    # Wirtualizacja
    virt-manager qemu-desktop libvirt edk2-ovmf

    # Biblioteki 32-bit (zoptymalizowane - usunięto duplikaty)
    lib32-mpg123 lib32-libvdpau lib32-libtheora lib32-speex
    lib32-libxrandr lib32-libxrender lib32-gamemode
    lib32-vulkan-swrast lib32-vkd3d lib32-alsa-plugins
    lib32-libpulse lib32-openal lib32-mangohud lib32-pipewire
)

# ── Dynamiczne dodawanie pakietów 32-bit dla GPU ──────────────
log_info "Dobieranie 32-bitowych bibliotek graficznych dla wykrytego układu: $GPU_TYPE"

case "$GPU_TYPE" in
    "nvidia")
        SYSTEM_PKGS+=(lib32-nvidia-utils lib32-vulkan-icd-loader)
        ;;
    "amd")
        SYSTEM_PKGS+=(lib32-vulkan-radeon lib32-mesa lib32-vulkan-mesa-layers lib32-mesa-utils lib32-vulkan-icd-loader)
        ;;
    "intel")
        SYSTEM_PKGS+=(lib32-libva-intel-driver lib32-vulkan-intel lib32-mesa lib32-vulkan-mesa-layers lib32-mesa-utils lib32-vulkan-icd-loader)
        ;;
    *)
        log_warn "GPU nierozpoznane lub brak specyficznych bibliotek 32-bit."
        ;;
esac

install_pacman_pkgs "${SYSTEM_PKGS[@]}"

# Dodanie repozytorium Flathub
log_info "Konfiguracja repozytorium Flathub"
sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo


# =============================================================
#  5. BOOTLOADER I KERNEL CMDLINE
# =============================================================
log_info "Konfiguracja bootloadera i /etc/kernel/cmdline"

CMDLINE="quiet splash"
[[ $GPU_TYPE == *"nvidia"* ]] && CMDLINE="$CMDLINE nvidia_drm.modeset=1"

# /etc/kernel/cmdline
if [ -f /etc/kernel/cmdline ]; then
    if ! grep -q "quiet splash" /etc/kernel/cmdline; then
        sudo sed -i "s/$/ $CMDLINE/" /etc/kernel/cmdline
        sudo sed -i 's/  */ /g'      /etc/kernel/cmdline
    fi
fi

# systemd-boot
for loader_root in "/boot" "/efi"; do
    if [ -d "$loader_root/loader/entries" ]; then
        [ -f "$loader_root/loader/loader.conf" ] && \
            sudo sed -i 's/^timeout .*/timeout 0/' "$loader_root/loader/loader.conf"

        for entry in "$loader_root/loader/entries/"*.conf; do
            if [ -f "$entry" ] && ! grep -q "quiet splash" "$entry"; then
                sudo sed -i "/^options/ s/$/ $CMDLINE/" "$entry"
                sudo sed -i 's/  */ /g' "$entry"
            fi
        done
    fi
done

# GRUB
if [ -f /etc/default/grub ]; then
    sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub
    sudo sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$CMDLINE\"|" \
        /etc/default/grub
    sudo grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null || \
    sudo grub-mkconfig -o /boot/GRUB/grub.cfg 2>/dev/null || true
fi


# =============================================================
#  6. PLYMOUTH + EARLY KMS
# =============================================================
log_info "Konfiguracja Plymouth"

sudo plymouth-set-default-theme -R bgrt 2>/dev/null || true

# Moduły GPU w mkinitcpio
if [[ $GPU_TYPE == *"nvidia"* ]]; then
    sudo sed -i 's/^MODULES=(/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm /' \
        /etc/mkinitcpio.conf
elif [[ $GPU_TYPE == *"amd"* ]]; then
    sudo sed -i 's/^MODULES=(/MODULES=(amdgpu /'  /etc/mkinitcpio.conf
elif [[ $GPU_TYPE == *"intel"* ]]; then
    sudo sed -i 's/^MODULES=(/MODULES=(i915 /'    /etc/mkinitcpio.conf
fi

sudo sed -i 's/^#Theme=.*/Theme=bgrt/'       /etc/plymouth/plymouthd.conf 2>/dev/null || true
sudo sed -i 's/^#ShowDelay=.*/ShowDelay=0/'  /etc/plymouth/plymouthd.conf 2>/dev/null || true

# Usunięcie przestarzałych opcji --splash z presetów
for preset in /etc/mkinitcpio.d/*.preset; do
    [ -f "$preset" ] && sudo sed -i 's/--splash [^ "]*//g' "$preset"
done

# Dodanie hooka Plymouth (jeśli brak)
if ! grep -q "plymouth" /etc/mkinitcpio.conf; then
    sudo sed -i 's/udev/udev plymouth/' /etc/mkinitcpio.conf
fi

sudo mkinitcpio -P


# =============================================================
#  7. USŁUGI, FIREWALL I OPTYMALIZACJA
# =============================================================
log_info "Konfiguracja usług, firewalla i logów"

# UFW – zezwolenie na forward (dla VM)
if [ -f /etc/default/ufw ]; then
    sudo sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' \
    /etc/default/ufw
fi

if command -v ufw &>/dev/null; then
    sudo systemctl enable --now ufw || true
    sudo ufw allow in  on virbr0 || true
    sudo ufw allow out on virbr0 || true
fi

# Włączanie usług systemowych
sudo systemctl enable --now geoclue.service || true
sudo systemctl enable --now ananicy-cpp || true
sudo systemctl enable --now fstrim.timer || true
sudo systemctl enable --now bluetooth || true
echo "options btusb enable_autosuspend=0" | sudo tee /etc/modprobe.d/btusb.conf
sudo systemctl enable --now libvirtd || true
sudo virsh net-autostart default || true

# Skrócenie domyślnego timeoutu zatrzymywania usług do 3s
sudo sed -i 's/^#\?[[:space:]]*DefaultTimeoutStopSec=.*/DefaultTimeoutStopSec=3s/' /etc/systemd/system.conf

# Wyłączenie zbędnej usługi opóźniającej boot
sudo systemctl disable NetworkManager-wait-online.service || true

# Czyszczenie starych logów (zachowanie ostatnich 2 dni)
sudo journalctl --vacuum-time=2d || true

# Konfiguracja BleachBit dla roota
if [ -d "$SCRIPT_DIR/bleachbit" ]; then
    sudo mkdir -p /root/.config/bleachbit
    sudo cp -af "$SCRIPT_DIR/bleachbit/." /root/.config/bleachbit/
    log_ok "Skopiowano konfigurację BleachBit"
else
    log_warn "Folder $SCRIPT_DIR/bleachbit nie istnieje – pominięto"
fi

# Dodanie użytkownika do grup wirtualizacji
sudo usermod -aG libvirt,kvm "$CURRENT_USER"


# =============================================================
#  8. KONFIGURACJA UŻYTKOWNIKA (ZSH, AUR)
# =============================================================

# ── ZSH + Oh My Zsh + Powerlevel10k ──────────────────────────
log_info "Konfiguracja ZSH"
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

        # Polskie locale + fastfetch przy starcie
        if ! grep -q "LC_ALL=pl_PL.UTF-8" ~/.zshrc; then
            {
                echo ""
                echo "export LC_ALL=pl_PL.UTF-8"
                echo "export LC_MESSAGES=pl_PL.UTF-8"
                echo "fastfetch"
            } >> ~/.zshrc
        fi
    fi
fi

# ── YAY (AUR helper) ──────────────────────────────────────────
log_info "Instalacja yay"
if ! command -v yay &> /dev/null; then
    rm -rf /tmp/yay
    git clone https://aur.archlinux.org/yay.git /tmp/yay
    (cd /tmp/yay && makepkg -si --noconfirm)
fi

yay --save --cleanafter --cleanmenu=false --diffmenu=false --editmenu=false

# ── Pakiety AUR ───────────────────────────────────────────────
log_info "Instalacja pakietów z AUR"

AUR_PKGS=(
    ventoy-bin
    lsfg-vk-bin
    google-chrome
    brave-bin
    faugus-launcher
    shelly-bin
    dmemcg-booster
    needrestart
    makeself
)

install_yay_pkgs "${AUR_PKGS[@]}"

# ── Usunięcie tymczasowego wyjątku sudo ───────────────────────
sudo rm -f /etc/sudoers.d/99-temp-installer

log_ok "KONFIGURACJA ZAKOŃCZONA SUKCESEM!"
sleep 3
systemctl reboot
