#!/bin/bash

# Kolory dla lepszej czytelności
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}======================================================${NC}"
echo -e "${BLUE}       KOMPLEKSOWY SKRYPT AKTUALIZACJI I CZYSZCZENIA  ${NC}"
echo -e "${BLUE}======================================================${NC}"

# 1. ZAPYTANIE O HASŁO TYLKO RAZ NA POCZĄTKU
echo -e "${YELLOW}Proszę podać hasło administratora (sudo) na potrzeby czyszczenia systemu:${NC}"
sudo -v

# Utrzymanie aktywnej sesji sudo w tle, dopóki skrypt działa
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
SUDO_KEEP_ALIVE_PID=$!

echo -e "\n${GREEN}==> Aktualizacja archlinux-keyring (zapobieganie błędom PGP)...${NC}"
sudo pacman -Sy archlinux-keyring --noconfirm

echo -e "\n${GREEN}==> Wykonywanie pełnej aktualizacji systemu (YAY)...${NC}"
yay -Syu --noconfirm

# AKTUALIZACJA FLATPAK
if command -v flatpak &> /dev/null; then
    echo -e "\n${GREEN}==> Wykonywanie aktualizacji aplikacji Flatpak...${NC}"
    flatpak update -y
fi

echo -e "\n${BLUE}======================================================${NC}"
echo -e "${BLUE}       FAZA 1: KOMENDY SYSTEMOWE (SUDO)               ${NC}"
echo -e "${BLUE}======================================================${NC}"

echo -e "${GREEN}==> Czyszczenie /var/lib/pacman/ (blokady i pliki tymczasowe)...${NC}"
sudo rm -f /var/lib/pacman/db.lck
sudo find /var/lib/pacman/ -type f -name "*.part" -delete

echo -e "${GREEN}==> Usuwanie osieroconych pakietów...${NC}"
ORPHANS=$(pacman -Qtdq)
if [ -n "$ORPHANS" ]; then
    sudo pacman -Rns $ORPHANS --noconfirm
else
    echo "Brak osieroconych pakietów."
fi

echo -e "${GREEN}==> Całkowite usuwanie zawartości cache pacmana...${NC}"
sudo rm -rf /var/cache/pacman/pkg/download-* 2>/dev/null
sudo rm -rf /var/cache/pacman/pkg/* 2>/dev/null

# BEZPIECZNE CZYSZCZENIE FLATPAK (SYSTEM)
if command -v flatpak &> /dev/null; then
    echo -e "${GREEN}==> Kompleksowe czyszczenie Flatpak (System)...${NC}"
    sudo flatpak uninstall --unused --system --delete-data -y
    sudo flatpak repair --system

    # Usuwanie nieużywanych źródeł (remotes)
    echo -e "${GREEN}==> Usuwanie nieużywanych źródeł (remotes) Flatpak...${NC}"
    USED_REMOTES=$(flatpak list --columns=origin 2>/dev/null | sort -u)
    ALL_REMOTES=$(flatpak remotes --columns=name 2>/dev/null)

    while IFS= read -r remote; do
        if [ -n "$remote" ] && ! echo "$USED_REMOTES" | grep -qx "$remote"; then
            echo -e "${YELLOW}Usuwanie nieużywanego źródła: $remote${NC}"
            sudo flatpak remote-delete --force "$remote" 2>/dev/null
        fi
    done <<< "$ALL_REMOTES"

    # Czyszczenie cache, plików tymczasowych i historii
    sudo rm -rf /var/tmp/flatpak-cache-* 2>/dev/null
    sudo rm -rf /var/lib/flatpak/repo/tmp/* 2>/dev/null
    sudo find /var/lib/flatpak -name "*.tmp" -delete 2>/dev/null
    sudo rm -f /var/lib/flatpak/history 2>/dev/null
else
    echo -e "${YELLOW}==> Flatpak nieobecny w systemie - pomijam czyszczenie systemowe.${NC}"
fi

echo -e "${GREEN}==> Czyszczenie logów w /var/log (rotate + usuwanie starych .gz)...${NC}"
sudo journalctl --vacuum-time=7d
sudo find /var/log -type f -name "*.gz" -mtime +14 -exec rm -f {} +

echo -e "${GREEN}==> Czyszczenie starego /tmp i /var/tmp...${NC}"
sudo find /tmp -type f -atime +5 -exec rm -f {} + 2>/dev/null
sudo find /var/tmp -type f -atime +5 -exec rm -f {} + 2>/dev/null

echo -e "\n${BLUE}======================================================${NC}"
echo -e "${BLUE}       FAZA 2: KOMENDY UŻYTKOWNIKA (BEZ SUDO)         ${NC}"
echo -e "${BLUE}======================================================${NC}"

echo -e "${GREEN}==> Całkowite czyszczenie cache YAY i źródeł AUR...${NC}"
yay -Scc --noconfirm
rm -rf ~/.cache/yay/* 2>/dev/null

# BEZPIECZNE CZYSZCZENIE FLATPAK (USER)
if command -v flatpak &> /dev/null; then
    echo -e "${GREEN}==> Kompleksowe czyszczenie Flatpak (Użytkownik)...${NC}"
    flatpak uninstall --unused --user --delete-data -y
    flatpak repair --user
    rm -f ~/.local/share/flatpak/history 2>/dev/null
else
    echo -e "${YELLOW}==> Flatpak nieobecny w systemie - pomijam czyszczenie użytkownika.${NC}"
fi

echo -e "${GREEN}==> Czyszczenie starego cache użytkownika (omijanie przeglądarek)...${NC}"
find ~/.cache -type f -atime +14 \
    ! -path "*/mozilla/*" \
    ! -path "*/google-chrome/*" \
    ! -path "*/chromium/*" \
    ! -path "*/BraveSoftware/*" \
    ! -path "*/opera/*" \
    ! -path "*/vivaldi/*" \
    ! -path "*/thorium/*" \
    -exec rm -f {} + 2>/dev/null

echo -e "${GREEN}==> Czyszczenie starych miniatur (thumbnails)...${NC}"
find ~/.cache/thumbnails -type f -atime +14 -exec rm -f {} + 2>/dev/null

echo -e "${GREEN}==> Przebudowa cache czcionek...${NC}"
fc-cache -r

echo -e "${GREEN}==> Czyszczenie virt-manager i reset dconf...${NC}"
USER_ID=$(id -u)
if [ -S "/run/user/$USER_ID/bus" ]; then
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_ID/bus" dconf reset /org/virt-manager/virt-manager/urls/isos 2>/dev/null
    echo -e "==> dconf reset wykonany."
fi
rm -rf "$HOME/.cache/virt-manager" 2>/dev/null

echo -e "\n${BLUE}======================================================${NC}"
echo -e "${BLUE}       FAZA 3: SPRAWDZANIE KONIECZNOŚCI RESTARTU      ${NC}"
echo -e "${BLUE}======================================================${NC}"

if command -v needrestart &> /dev/null; then
    echo -e "${GREEN}==> Analiza zaktualizowanych pakietów (needrestart)...${NC}"

    # Uruchamiamy needrestart z flagą -b (batch), żeby nie blokował skryptu
    NEEDRESTART_OUT=$(sudo needrestart -b 2>/dev/null)

    if echo "$NEEDRESTART_OUT" | grep -q "KRESTART: 1"; then
        echo -e "\n${RED}******************************************************${NC}"
        echo -e "${RED} UWAGA: Zaktualizowano kluczowe komponenty (np. kernel)! ${NC}"
        echo -e "${YELLOW} ZALECANY JEST RESTART KOMPUTERA!                     ${NC}"
        echo -e "${RED}******************************************************${NC}\n"
    else
        echo -e "${GREEN}==> Restart systemu nie jest aktualnie wymagany.${NC}"
    fi
else
    echo -e "${YELLOW}Brak programu 'needrestart'. Używam metody zapasowej (sprawdzanie modułów)...${NC}"
    if [ ! -d "/usr/lib/modules/$(uname -r)" ]; then
        echo -e "\n${RED}******************************************************${NC}"
        echo -e "${RED} UWAGA: Zaktualizowano kernel!                        ${NC}"
        echo -e "${YELLOW} ZALECANY JEST RESTART KOMPUTERA!                     ${NC}"
        echo -e "${RED}******************************************************${NC}\n"
    else
        echo -e "${GREEN}==> Nie wykryto aktualizacji kernela wymagającej restartu.${NC}"
    fi
fi

# Zatrzymanie procesu podtrzymującego sudo w tle
kill $SUDO_KEEP_ALIVE_PID 2>/dev/null

echo -e "\n${GREEN}======================================================${NC}"
echo -e "${GREEN}       AKTUALIZACJA I CZYSZCZENIE ZAKOŃCZONE!          ${NC}"
echo -e "${GREEN}======================================================${NC}"
echo "Naciśnij [ENTER], aby zakończyć..."
read -r
