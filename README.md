# ArchInstallerTool

Arabic documentation: [README.ar.md](README.ar.md)

ArchInstallerTool is an interactive Bash installer for Arch Linux. It is designed to run from the official Arch Linux live ISO and guide the user through network setup, mirror handling, installation profiles, desktop selection, disk partitioning, package installation, bootloader setup, and post-install tasks.

> **Warning:** This tool can erase disks. Read the warnings, verify the target disk, and understand what each option does before continuing.

## Features

- Interactive installation profiles: minimal, desktop, server, developer, gaming, and custom.
- Wi-Fi connection helper using `nmcli` or `iwctl`.
- Optional pacman mirror optimization with backup and restore.
- Kernel selection: `linux`, `linux-lts`, `linux-zen`, `linux-hardened`.
- Matching `linux-headers` package installation.
- Desktop environment selection: KDE, GNOME, XFCE, i3, Sway, Hyprland, or none.
- Filesystem selection: `ext4`, `btrfs`, or `xfs`.
- Btrfs subvolumes: `@`, `@home`, and `@snapshots`.
- Automatic simple partitioning and LVM partitioning.
- GPU driver selection and detection for Intel, AMD, NVIDIA Open DKMS, and virtual machines.
- Arabic and English locale options, including `ar_IQ.UTF-8`.
- Username and hostname validation.
- Package validation before disk formatting.
- Improved failure reporting with the failed step, command, line number, and log tail.
- Post-install script generation for AUR tools and profile-specific setup.

## Requirements

Run this script from the official Arch Linux live environment.

Recommended:

- UEFI-capable machine if you want UEFI boot.
- Working internet connection.
- Root shell in the Arch ISO.
- A backup of all important data.
- Basic knowledge of Linux disks and partitions.

The script expects common Arch ISO tools such as:

```bash
pacstrap arch-chroot genfstab pacman parted lsblk systemctl
```

For some options, additional tools are required:

```bash
mkfs.btrfs mkfs.xfs lvm2 reflector nmcli iwctl
```

## Quick Start

From the Arch live ISO:

```bash
chmod +x ArchInstallerTool.sh
./ArchInstallerTool.sh
```

If the script exits or fails, read the error output and check the log path printed by the installer.

## Method 1: Download From Another Computer Over HTTP

On the computer that has the script:

```bash
cd /path/to/script-folder
python3 -m http.server 8000 --bind 0.0.0.0
```

Find that computer's IP address:

```bash
ip -4 addr
```

On the target Arch live machine:

```bash
curl -fL http://IP_ADDRESS:8000/ArchInstallerTool.sh -o ArchInstallerTool.sh
chmod +x ArchInstallerTool.sh
./ArchInstallerTool.sh
```

Example:

```bash
curl -fL http://192.168.1.207:8000/ArchInstallerTool.sh -o ArchInstallerTool.sh
chmod +x ArchInstallerTool.sh
./ArchInstallerTool.sh
```

If the download fails, test connectivity:

```bash
ping -c 3 IP_ADDRESS
curl -I http://IP_ADDRESS:8000/
```

## Method 2: Copy From a USB Drive

Copy the script to a USB drive from another system. On the Arch live machine:

```bash
lsblk
mkdir -p /mnt/usb
mount /dev/sdX1 /mnt/usb
cp /mnt/usb/ArchInstallerTool.sh .
chmod +x ArchInstallerTool.sh
./ArchInstallerTool.sh
```

Replace `/dev/sdX1` with the real USB partition shown by `lsblk`.

## Method 3: Transfer With SCP Over SSH

On the Arch live target machine, set a temporary root password and start SSH:

```bash
passwd
systemctl start sshd
ip -4 addr
```

From your main computer:

```bash
scp ArchInstallerTool.sh root@TARGET_IP:/root/ArchInstallerTool.sh
```

Then on the Arch live target:

```bash
chmod +x /root/ArchInstallerTool.sh
/root/ArchInstallerTool.sh
```

## Method 4: Download From GitHub

After publishing the repository, you can download the raw file:

```bash
curl -fL https://raw.githubusercontent.com/Arai1355/ArchInstallerTool/main/ArchInstallerTool.sh -o ArchInstallerTool.sh
chmod +x ArchInstallerTool.sh
./ArchInstallerTool.sh
```

Repository page: <https://github.com/Arai1355/ArchInstallerTool>

## Method 5: Clone the Repository With Git

This method is useful when you want the full repository, including the README files and future project files.

First, connect the Arch live environment to the network.

For Ethernet, it usually works automatically. Test it:

```bash
ping -c 3 archlinux.org
```

For Wi-Fi, use `iwctl`:

```bash
iwctl
```

Inside the `iwctl` prompt:

```text
device list
station wlan0 scan
station wlan0 get-networks
station wlan0 connect WIFI_NAME
exit
```

Replace `wlan0` with your real wireless interface and `WIFI_NAME` with your network name. If the network has a password, `iwctl` will ask for it.

Test the connection:

```bash
ping -c 3 archlinux.org
```

If `git` is not available in the live environment, install it:

```bash
pacman -Sy git
```

Clone the repository:

```bash
git clone https://github.com/Arai1355/ArchInstallerTool.git
cd ArchInstallerTool
chmod +x ArchInstallerTool.sh
./ArchInstallerTool.sh
```

You can also clone a specific branch:

```bash
git clone -b BRANCH_NAME https://github.com/Arai1355/ArchInstallerTool.git
```

## Verify the Script Before Running

Always inspect scripts before executing them as root:

```bash
less ArchInstallerTool.sh
```

Run a syntax check:

```bash
bash -n ArchInstallerTool.sh
```

If a trusted checksum is published, verify it:

```bash
sha256sum ArchInstallerTool.sh
```

Do not run a script if the checksum does not match the trusted value.

## Important Safety Warnings

- This script can destroy all data on the selected target disk.
- Do not select the USB installer drive as the target disk.
- Always check disks with:

```bash
lsblk -f
fdisk -l
```

- Automatic partitioning formats the selected disk.
- Manual partitioning still requires care; wrong partition names can destroy data.
- LVM, Btrfs, bootloaders, and GPU drivers can affect boot behavior.
- Laptop users should connect AC power before starting.
- Do not interrupt `pacstrap`, formatting, bootloader installation, or `mkinitcpio`.

## Security Warning

Never blindly run installation scripts from unknown sources.

A modified copy of this script could:

- Erase unexpected disks.
- Download malicious packages.
- Add unauthorized SSH keys.
- Change passwords or users.
- Install backdoors or remote access tools.
- Exfiltrate private data if network access is available.

Before running:

```bash
less ArchInstallerTool.sh
bash -n ArchInstallerTool.sh
sha256sum ArchInstallerTool.sh
```

Prefer downloading from your own repository, a verified release, or a checksum you trust.

## Legal Disclaimer

This project is provided as-is, without warranty of any kind.

The author is not responsible for:

- Data loss.
- Broken installations.
- Boot failures.
- Hardware or firmware misconfiguration.
- Security incidents caused by modified or malicious copies.
- Damage caused by running the script without understanding its behavior.

You are responsible for reviewing the code, backing up your data, selecting the correct disk, and verifying the source of any script you run as root.

## Recovery Tips

If something fails, check mounts and disks:

```bash
findmnt /mnt
lsblk -f
```

Unmount before retrying:

```bash
umount -R /mnt 2>/dev/null
swapoff -a
```

Check the installation log printed by the script, usually under:

```bash
/tmp/arch_installer_*/install.log
```

## Recommended Workflow

1. Boot the official Arch Linux ISO.
2. Connect to the internet.
3. Transfer or download `ArchInstallerTool.sh`.
4. Inspect and verify the script.
5. Run `bash -n ArchInstallerTool.sh`.
6. Run the installer.
7. Carefully select the target disk.
8. Review the summary before typing `yes`.
9. Reboot only after the installer completes successfully.

## Notes

- Secure Boot and full disk encryption are advanced features and should be implemented carefully.
- For production systems, review the generated configuration and bootloader setup before relying on the installation.
- Keep a rescue USB available.
