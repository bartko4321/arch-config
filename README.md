# 🐧 Arch Linux – Post-Installation & Configuration Script

This project contains a comprehensive Bash shell script (`install.sh`) designed to automate the configuration of an Arch Linux system right after installation. The script installs essential packages, optimizes the package manager, sets up the user environment, and automatically adjusts system services and the bootloader to match your hardware.

## 🚀 Key Features

* **Hardware Detection (GPU):** Automatically detects your graphics card (NVIDIA, AMD, Intel) and installs the appropriate 32-bit libraries (including Vulkan) and loads the correct modules for Early KMS.
* **Package Management:**
  * Installs a wide selection of system, development, multimedia, and gaming applications via `pacman`.
  * Automatically installs `yay` for AUR support and uses it to install selected packages (e.g. Google Chrome, Brave, Ventoy).
  * Configures **Flathub** integration.
  * Removes a predefined list of unnecessary packages (bloatware).
* **`pacman.conf` Optimization:** Enables parallel downloads (`ParallelDownloads`), syntax coloring (`ILoveCandy`), and blocks unnecessary locale files (keeping only PL and EN) and documentation to save disk space.
* **Bootloader & Plymouth:** Configures a silent boot (`quiet splash`, hidden GRUB/systemd-boot menu) and a Plymouth splash screen.
* **Terminal Environment:** Changes the default shell to **ZSH**, installs the **Oh My Zsh** framework and the **Powerlevel10k** theme, and adds `fastfetch` on startup.
* **Privacy & Networking:** Forces the use of Cloudflare's secure DNS servers (1.1.1.1).
* **Services & Security:** Configures the firewall (UFW) and enables key system services (Bluetooth, fstrim, libvirt/KVM).

## ⚠️ Prerequisites

1. A fresh **Arch Linux** installation.
2. `sudo` configured — the script **must not** be run as root; run it as a regular user with `sudo` privileges.
3. An active internet connection.

## 💻 Installation & Usage

1. Clone the repository to your disk
   ```bash
   git clone https://github.com/bartko4321/arch-config.git
   ```

2. Navigate to the folder
   ```bash
   cd arch-config
   ```

3. Make the script executable
   ```bash
   chmod +x install.sh
   ```

4. Run the script (without `sudo`!)
   ```bash
   ./install.sh
   ```

5. Running inside a chroot
   ```bash
   sudo -u username /home/username/kde-config-kde/install.sh
   ```

6. The script will prompt you for:
   * Your `sudo` password (to temporarily elevate privileges during installation)

Once finished, the script will **automatically reboot your computer**.

## 🛠 Configuration & Customization

The script is written to be easily tailored to your needs. Open `install.sh` in any text editor to:
* Modify the list of packages to remove in the `PACKAGES_TO_REMOVE` section.
* Add/remove official packages in the `SYSTEM_PKGS` array.
* Add/remove AUR packages in the `AUR_PKGS` array.
* Change default services (e.g. disable UFW or libvirt).

## 📁 Optional File Structure

The script checks for and copies additional files if they are present in the same directory:
* `.update.sh` – an optional user update script.
* `System Maintenance.desktop` – a desktop/menu shortcut file.
* `bleachbit/` folder – pre-configured settings for BleachBit.

* Support account number: 06291000060000000005038936

* If you find this project useful, leave a star! ⭐

## 🛑 Important Notice (Disclaimer)

This script modifies critical system files (such as `/etc/pacman.conf`, `/etc/mkinitcpio.conf`, GRUB settings). Make sure you have read and understand what the code does before running it. The project is provided "as-is", without any warranty.
