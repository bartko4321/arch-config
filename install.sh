#!/bin/bash
# =============================================================
#  SKRYPT INSTALACYJNY - Arch Linux
# =============================================================

set -euo pipefail

# ── Wykrywanie języka systemu ──────────────────────────────────
# Jeśli system jest ustawiony na polski (pl_PL/pl_*) -> komunikaty PL,
# w każdym innym przypadku -> komunikaty EN.
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

# ── Kolory ────────────────────────────────────────────────────
INFO='\033[0;34m'
SUCCESS='\033[0;32m'
WARN='\033[0;33m'
ERR='\033[0;31m'
NC='\033[0m'

# ── System logowania ───────────────────────────────────────────
# Zasada: na ekranie widoczne są TYLKO ważne komunikaty ogólne
# (log_info / log_ok / log_error). Wszystko inne (log_warn – szczegóły,
# pominięcia, drobne problemy) trafia WYŁĄCZNIE do pliku logu.
# Plik logu jest tworzony na stałe tylko wtedy, gdy wystąpi błąd
# (skrypt zakończy się kodem innym niż 0) – w przeciwnym razie
# tymczasowy log jest po prostu kasowany na końcu.
TMP_LOG="$(mktemp /tmp/install-log.XXXXXX)"
LOG_FILE="$HOME/install_error_$(date +%Y%m%d_%H%M%S).log"

# fd 3 = prawdziwy terminal (do wyświetlania ważnych komunikatów),
# fd 1/2 od teraz lądują wyłącznie w pliku tymczasowym (ukryte).
exec 3>&1
exec >>"$TMP_LOG" 2>&1

cleanup_on_exit() {
    local exit_code=$?
    if [ "$exit_code" -ne 0 ]; then
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

# ── Pomocnicze funkcje logowania ──────────────────────────────
# Każda funkcja przyjmuje: "$1" = tekst PL, "$2" = tekst EN
_pick_msg() { [[ "$SCRIPT_LANG" == "pl" ]] && echo "$1" || echo "$2"; }

log_info()  { local m; m="$(_pick_msg "$1" "$2")"; echo -e "${INFO}==> $m${NC}" >&3; echo -e "${INFO}==> $m${NC}"; }
log_ok()    { local m; m="$(_pick_msg "$1" "$2")"; echo -e "${SUCCESS}✔ $m${NC}" >&3; echo -e "${SUCCESS}✔ $m${NC}"; }
log_error() { local m; m="$(_pick_msg "$1" "$2")"; echo -e "${ERR}✘ $m${NC}" >&3; echo -e "${ERR}✘ $m${NC}"; }
# log_warn: celowo NIE trafia na ekran (fd 3) - tylko do logu w tle
log_warn()  { local m; m="$(_pick_msg "$1" "$2")"; echo -e "${WARN}⚠ $m${NC}"; }

# Upewnij się, że skrypt NIE jest uruchamiany jako root
if [[ "$EUID" -eq 0 ]]; then
    log_error "Nie uruchamiaj skryptu jako root. Uruchom jako zwykły użytkownik z sudo." \
               "Do not run this script as root. Run it as a regular user with sudo."
    exit 1
fi

# ── Funkcje filtrujące pakiety przed instalacją ───────────────
install_pacman_pkgs() {
    local valid_pkgs=()
    for pkg in "$@"; do
        if pacman -Si "$pkg" &>/dev/null; then
            valid_pkgs+=("$pkg")
        else
            log_warn "Pomijam pakiet (nie znaleziono w oficjalnych repozytoriach): $pkg" \
                     "Skipping package (not found in official repositories): $pkg"
        fi
    done

    if [ ${#valid_pkgs[@]} -gt 0 ]; then
        sudo pacman -S --noconfirm --needed "${valid_pkgs[@]}"
    else
        log_warn "Brak prawidłowych pakietów do zainstalowania z podanej listy." \
                 "No valid packages to install from the given list."
    fi
}

install_yay_pkgs() {
    local valid_pkgs=()
    for pkg in "$@"; do
        if yay -Si "$pkg" &>/dev/null; then
            valid_pkgs+=("$pkg")
        else
            log_warn "Pomijam pakiet z AUR (nie znaleziono): $pkg" \
                     "Skipping AUR package (not found): $pkg"
        fi
    done

    if [ ${#valid_pkgs[@]} -gt 0 ]; then
        yay -S --noconfirm --needed "${valid_pkgs[@]}"
    else
        log_warn "Brak prawidłowych pakietów AUR do zainstalowania z podanej listy." \
                 "No valid AUR packages to install from the given list."
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

# ── Kopiowanie .local i .config do katalogu domowego ──────────
if [ -d "$SCRIPT_DIR/.local" ]; then
    mkdir -p ~/.local
    cp -afT "$SCRIPT_DIR/.local" ~/.local
    log_ok "Skopiowano katalog '.local' do \$HOME" \
           "Copied '.local' directory to \$HOME"
else
    log_warn "Brak katalogu '.local' w katalogu skryptu – pominięto" \
             "No '.local' directory in script folder – skipped"
fi

if [ -d "$SCRIPT_DIR/.config" ]; then
    mkdir -p ~/.config
    cp -afT "$SCRIPT_DIR/.config" ~/.config
    log_ok "Skopiowano katalog '.config' do \$HOME" \
           "Copied '.config' directory to \$HOME"
else
    log_warn "Brak katalogu '.config' w katalogu skryptu – pominięto" \
             "No '.config' directory in script folder – skipped"
fi


# =============================================================
#  3. KONFIGURACJA SYSTEMOWA (wymaga sudo)
# =============================================================
log_info "Rozpoczynanie konfiguracji systemowej" \
         "Starting system configuration"

# ── Tymczasowy wyjątek sudo dla pacmana ───────────────────────
sudo -v
echo "$CURRENT_USER ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/99-temp-installer > /dev/null

# ── Usuwanie niechcianych pakietów ────────────────────────────
PACKAGES_TO_REMOVE="htop nano konqueror plasma-browser-integration plasma-vault krdp krfb plasma-thunderbolt kontact kmail kontrast plasma-welcome imagemagick kaddressbook kdepim-runtime akonadi-server akregator korganizer gnome-software epiphany decibels rhythmbox showtime cosmic-store cosmic-player parole kwalletmanager"

INSTALLED_PACKAGES=$(pacman -Qq $PACKAGES_TO_REMOVE 2>/dev/null || true)

if [ -n "$INSTALLED_PACKAGES" ]; then
    # shellcheck disable=SC2086
    sudo pacman -Rs --noconfirm $INSTALLED_PACKAGES 2>/dev/null || true
fi

# --- Wyłączenie KDE Wallet (Portfela) ---
log_info "Wyłączanie usługi KDE Wallet..." \
         "Disabling KDE Wallet service..."
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

# ── Optymalizacja pacmana ─────────────────────────────────────
log_info "Optymalizacja /etc/pacman.conf..." \
         "Optimizing /etc/pacman.conf..."

sudo sed -i 's/^#[[:space:]]*Color/Color/' /etc/pacman.conf
if ! grep -qw "ILoveCandy" /etc/pacman.conf; then
    sudo sed -i '/^Color/a ILoveCandy' /etc/pacman.conf
fi
sudo sed -i 's/^[[:space:]]*CheckSpace/#CheckSpace/' /etc/pacman.conf
sudo sed -i 's/^#[[:space:]]*ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
sudo sed -i 's/^ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
sudo sed -i 's/^#[[:space:]]*VerbosePkgLists/VerbosePkgLists/' /etc/pacman.conf

# Blokowanie wypakowywania wszystkich języków z wyjątkiem PL i EN oraz dokumentacji CUPS
log_info "Dodawanie reguł NoExtract (języki i dokumentacja CUPS)..." \
         "Adding NoExtract rules (languages and CUPS documentation)..."
if ! grep -q "NoExtract = usr/share/locale" /etc/pacman.conf; then
    sudo sed -i '/^\[options\]/a NoExtract = usr/share/locale/* !usr/share/locale/pl* !usr/share/locale/en*\nNoExtract = usr/share/cups/doc/*' /etc/pacman.conf
fi

# Blokowanie wypakowywania dokumentacji i stron podręcznika
log_info "Dodawanie reguł NoExtract (dokumentacja i man pages)..." \
         "Adding NoExtract rules (documentation and man pages)..."
if ! grep -q "NoExtract = usr/share/man" /etc/pacman.conf; then
    sudo sed -i '/NoExtract = usr\/share\/cups\/doc/a NoExtract = usr/share/man/*\nNoExtract = usr/share/doc/*\nNoExtract = usr/share/info/*\nNoExtract = usr/share/gtk-doc/*\nNoExtract = usr/share/help/*' /etc/pacman.conf
fi

# Przeinstalowanie pakietu cups, aby zastosować reguły i wyczyścić stare pliki
log_info "Instalacja/Przeinstalowanie CUPS..." \
         "Installing/Reinstalling CUPS..."
sudo pacman -S --noconfirm cups

# DNS CLOUDFLARE
# ============================================================
log_info "Konfiguracja DNS (NetworkManager)..." \
         "Configuring DNS (NetworkManager)..."

# Przygotowanie konfiguracji dla NetworkManagera (zastosuje się PO RESTARCIE)
sudo mkdir -p /etc/NetworkManager/conf.d
echo -e "[main]\ndns=default\nrc-manager=symlink" | sudo tee /etc/NetworkManager/conf.d/dns.conf > /dev/null

# Globalne DNS dla NM (IPv4 + IPv6 od Cloudflare)
echo -e "[global-dns]\n\n[global-dns-domain-*]\nservers=1.1.1.1,1.0.0.1,2606:4700:4700::1112,2606:4700:4700::1002" | sudo tee /etc/NetworkManager/conf.d/global-dns.conf > /dev/null

log_ok "DNS został skonfigurowany w NetworkManagerze (zacznie działać na gotowym systemie po restarcie)." \
       "DNS has been configured in NetworkManager (will take effect after the system restarts)."

# =============================================================
#  4. INSTALACJA PAKIETÓW OFICJALNYCH I FLATHUB
# =============================================================
log_info "Instalacja pakietów systemowych" \
         "Installing system packages"
sudo pacman -Syu --noconfirm

SYSTEM_PKGS=(
    # System i narzędzia
    base-devel git zsh pacman-contrib fastfetch reflector
    gcc make cmake meson ninja just
    python-pip python-tqdm python-defusedxml python-packaging
    gwenview okular ark

    # Zarządzanie systemem i dyskami
    partitionmanager bleachbit unrar mc btrfs-progs exfat-utils ntfs-3g os-prober
    fsarchiver inxi pv rsync 7zip zenity innoextract android-tools dnsmasq vde2 cdemu-client cdemu-daemon vhba-module

    # Narzędzia wizualne i systemowe
    plymouth profile-sync-daemon ananicy-cpp dconf-editor geoclue fwupd fwupd-efi
    bluez-obex appmenu-gtk-module libayatana-appindicator flatpak timeshift
    thunderbird thunderbird-i18n-pl zsh-syntax-highlighting zsh-autosuggestions

    # Multimedia i grafika
    vlc vlc-plugins-all libappimage handbrake
    krita krita-plugin-gmic gimp gmic
    audacity qmmp mixxx kdenlive soundconverter
    gst-plugins-good gst-plugins-bad gst-plugins-ugly

    # Komunikatory i sieć
    discord telegram-desktop qbittorrent firefox-developer-edition firefox-developer-edition-i18n-pl

    # Biuro
    libreoffice-fresh libreoffice-fresh-pl hunspell-pl

    # WINE, Gaming i Wirtualizacja
    wine-staging winetricks gamemode gamescope mangohud goverlay vkd3d
    vulkan-dzn vulkan-gfxstream vulkan-swrast
    virt-manager qemu-desktop libvirt edk2-ovmf

    # Biblioteki 32-bit (zoptymalizowane - bez duplikatów)
    lib32-mpg123 lib32-libvdpau lib32-libtheora lib32-speex
    lib32-libxrandr lib32-libxrender lib32-gamemode
    lib32-vulkan-swrast lib32-vkd3d lib32-alsa-plugins
    lib32-libpulse lib32-openal lib32-mangohud lib32-pipewire
)

# ── Dynamiczne dodawanie pakietów 32-bit dla GPU ──────────────
log_info "Dobieranie 32-bitowych bibliotek graficznych dla wykrytego układu: $GPU_TYPE" \
         "Selecting 32-bit graphics libraries for detected GPU: $GPU_TYPE"

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
        log_warn "GPU nierozpoznane lub brak specyficznych bibliotek 32-bit." \
                 "GPU not recognized or no specific 32-bit libraries available."
        ;;
esac

install_pacman_pkgs "${SYSTEM_PKGS[@]}"

# Dodanie repozytorium Flathub
log_info "Konfiguracja repozytorium Flathub" \
         "Configuring the Flathub repository"
sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

log_info "Odświeżanie metadanych Flathub..." \
         "Refreshing Flathub metadata..."
sudo flatpak update --appstream

# Aplikacje Flatpak (Flathub)
sudo flatpak install -y flathub com.github.tchx84.Flatseal \
    || log_warn "Błąd instalacji Flatseal" "Error installing Flatseal"
sudo flatpak install -y flathub it.mijorus.gearlever \
    || log_warn "Błąd instalacji Gear Lever" "Error installing Gear Lever"


# =============================================================
#  5. BOOTLOADER I KERNEL CMDLINE
# =============================================================
log_info "Konfiguracja bootloadera i /etc/kernel/cmdline" \
         "Configuring bootloader and /etc/kernel/cmdline"

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
log_info "Konfiguracja Plymouth" \
         "Configuring Plymouth"

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
log_info "Konfiguracja usług, firewalla i logów" \
         "Configuring services, firewall and logs"

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

# Upewnij się, że sieć "default" istnieje, zanim spróbujemy ją włączyć/ustawić autostart
if ! sudo virsh net-info default &>/dev/null; then
    log_warn "Sieć 'default' nie jest zdefiniowana - definiuję z domyślnego XML..." \
             "Network 'default' is not defined - defining it from the default XML..."
    sudo virsh net-define /usr/share/libvirt/networks/default.xml || true
fi

sudo virsh net-start default 2>/dev/null || true
sudo virsh net-autostart default || log_warn "Nie udało się ustawić autostartu sieci 'default' - sprawdź 'virsh net-list --all'." \
                                            "Failed to enable autostart for network 'default' - check 'virsh net-list --all'."

# Skrócenie domyślnego timeoutu zatrzymywania usług do 3s
sudo sed -i 's/^#\?[[:space:]]*DefaultTimeoutStopSec=.*/DefaultTimeoutStopSec=3s/' /etc/systemd/system.conf

# Skrócenie domyślnego timeoutu uruchamiania usług do 3s
sudo sed -i 's/^#\?[[:space:]]*DefaultTimeoutStartSec=.*/DefaultTimeoutStartSec=3s/' /etc/systemd/system.conf

# Wyłączenie zbędnej usługi opóźniającej boot
sudo systemctl disable NetworkManager-wait-online.service || true

# Czyszczenie starych logów (zachowanie ostatnich 2 dni)
sudo journalctl --vacuum-time=2d || true

# Konfiguracja BleachBit dla roota
if [ -d "$SCRIPT_DIR/bleachbit" ]; then
    sudo mkdir -p /root/.config/bleachbit
    sudo cp -af "$SCRIPT_DIR/bleachbit/." /root/.config/bleachbit/
else
    log_warn "Folder $SCRIPT_DIR/bleachbit nie istnieje – pominięto" \
             "Folder $SCRIPT_DIR/bleachbit does not exist – skipped"
fi

# Dodanie użytkownika do grup wirtualizacji
sudo usermod -aG libvirt,kvm "$CURRENT_USER"


# =============================================================
#  8. KONFIGURACJA ZSH
# =============================================================

# ── ZSH + Oh My Zsh + Powerlevel10k ──────────────────────────
log_info "Konfiguracja ZSH" \
         "Configuring ZSH"
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

        # Polskie locale + fastfetch przy starcie
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

# =============================================================
#  9. YAY (AUR HELPER) I PAKIETY AUR
# =============================================================
log_info "Instalacja yay i pakietów AUR..." \
         "Installing yay and AUR packages..."

if ! command -v yay &>/dev/null; then
    rm -rf /tmp/yay
    git clone https://aur.archlinux.org/yay.git /tmp/yay
    (cd /tmp/yay && makepkg -si --noconfirm)
fi

yay --save --cleanafter --cleanmenu=false --diffmenu=false --editmenu=false

AUR_PKGS=(ventoy-bin lsfg-vk-bin google-chrome brave-origin-bin faugus-launcher shelly-bin dmemcg-booster needrestart makeself)
install_yay_pkgs "${AUR_PKGS[@]}"

# ── Usunięcie tymczasowego wyjątku sudo ───────────────────────
sudo rm -f /etc/sudoers.d/99-temp-installer

log_ok "KONFIGURACJA ZAKOŃCZONA SUKCESEM!" \
       "CONFIGURATION COMPLETED SUCCESSFULLY!"

# =============================================================
#  10. RESTART SYSTEMU
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
        log_info "Restartowanie systemu..." "Restarting the system..."
        sudo reboot
        ;;
    [Nn]*)
        log_info "Pominięto restart. Pamiętaj, aby zrestartować system później, aby zmiany zostały zastosowane." \
                  "Restart skipped. Remember to restart the system later for the changes to take effect."
        exit 0
        ;;
    *)
        log_info "Nieprawidłowy wybór. Pominięto restart. Pamiętaj, aby zrestartować system później, aby zmiany zostały zastosowane." \
                  "Invalid choice. Restart skipped. Remember to restart the system later for the changes to take effect."
        exit 0
        ;;
esac
