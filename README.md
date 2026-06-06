# 🐧 Arch Linux – Skrypt Poinstalacyjny i Konfiguracyjny

Ten projekt zawiera kompleksowy skrypt w powłoce Bash (`install.sh`), przeznaczony do automatyzacji konfiguracji systemu Arch Linux tuż po jego instalacji. Skrypt instaluje niezbędne pakiety, optymalizuje menedżera pakietów, konfiguruje środowisko użytkownika oraz automatycznie dostosowuje usługi systemowe i bootloader do posiadanego sprzętu.

## 🚀 Główne funkcje

* **Wykrywanie sprzętu (GPU):** Automatycznie rozpoznaje kartę graficzną (NVIDIA, AMD, Intel) i instaluje dedykowane 32-bitowe biblioteki (m.in. Vulkan) oraz ładuje odpowiednie moduły do wczesnego startu jądra (Early KMS).
* **Zarządzanie pakietami:**
  * Instaluje szeroką listę aplikacji systemowych, deweloperskich, multimedialnych i gamingowych za pomocą `pacman`.
  * Automatycznie instaluje narzędzie `yay` do obsługi repozytorium AUR i instaluje z niego wybrane pakiety (np. Google Chrome, Brave, Ventoy).
  * Konfiguruje integrację z **Flathub**.
  * Usuwa predefiniowaną listę zbędnych pakietów (bloatware).
* **Optymalizacja `pacman.conf`:** Włącza równoległe pobieranie (ParallelDownloads), kolorowanie składni (`ILoveCandy`) oraz blokuje pobieranie zbędnych plików językowych (zostawia tylko PL i EN) i dokumentacji w celu oszczędzania miejsca.
* **Bootloader i Plymouth:** Konfiguruje bezgłośny start systemu (`quiet splash`, ukrycie menu GRUB/systemd-boot) oraz ekran ładowania Plymouth.
* **Środowisko terminala:** Zmienia domyślną powłokę na **ZSH**, instaluje framework **Oh My Zsh** oraz motyw **Powerlevel10k**, dodając `fastfetch` na starcie.
* **Prywatność i sieć:** Wymusza korzystanie z bezpiecznych serwerów DNS od Cloudflare (1.1.1.1).
* **Usługi i bezpieczeństwo:** Konfiguruje zaporę sieciową (UFW) i włącza kluczowe usługi systemowe (Bluetooth, fstrim, libvirt/KVM).

## ⚠️ Wymagania wstępne

1. Świeża instalacja systemu **Arch Linux**.
2. Skonfigurowane sudo (skrypt **nie może** być uruchamiany jako root, musisz uruchomić go jako zwykły użytkownik posiadający uprawnienia do `sudo`).
3. Dostęp do Internetu.

## 💻 Instalacja i użycie

1. Sklonuj repozytorium na swój dysk:
   ```bash
   git clone https://github.com/bartko4321/arch-config.git
   cd arch-config
   ```

2. Nadaj skryptowi uprawnienia do wykonywania:
   ```bash
   chmod +x install.sh
   ```

3. Uruchom skrypt (bez `sudo`!):
   ```bash
   ./install.sh
   uruchamienie w chroot sudo -u nazwa-użytkownika /home/nazwa-użytkownika/kde-config-kde/install.sh
   ```

4. Skrypt poprosi Cię o:
   * Hasło `sudo` (aby nadać sobie tymczasowe uprawnienia na czas instalacji)

Po zakończeniu działania skrypt **automatycznie zrestartuje komputer**.

## 🛠 Konfiguracja i modyfikacja

Skrypt został napisany tak, aby łatwo było go dostosować do własnych potrzeb. Otwórz `install.sh` w dowolnym edytorze tekstu, aby:
* Zmodyfikować listę pakietów do odinstalowania w sekcji `PACKAGES_TO_REMOVE`.
* Dodać/usunąć oficjalne pakiety w tablicy `SYSTEM_PKGS`.
* Dodać/usunąć pakiety z AUR w tablicy `AUR_PKGS`.
* Zmienić domyślne usługi (np. deaktywować UFW czy libvirt).

## 📁 Struktura opcjonalnych plików

Skrypt sprawdza obecność i kopiuje dodatkowe pliki, jeśli znajdują się w tym samym katalogu:
* `.update.sh` – opcjonalny skrypt aktualizacyjny użytkownika.
* `Konserwacja systemu.desktop` – plik skrótu na pulpit/do menu.
* Folder `bleachbit/` – prekonfigurowane ustawienia dla programu BleachBit.

## 🛑 Ważna uwaga (Disclaimer)

Ten skrypt modyfikuje krytyczne pliki systemowe (takie jak `/etc/pacman.conf`, `/etc/mkinitcpio.conf`, ustawienia GRUB). Upewnij się, że przeczytałeś i rozumiesz, co robi kod, przed jego uruchomieniem. Projekt jest dostarczany "tak jak jest" (as-is), bez żadnej gwarancji.
