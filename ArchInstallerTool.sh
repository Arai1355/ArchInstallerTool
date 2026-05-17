#!/bin/bash
# =============================================================================
# Arch Linux Ultimate Installer - Professional Installation Tool
# Version: 2.0
# Description: Interactive menu-driven Arch Linux installation with multiple
#              installation profiles, advanced partitioning, and customization
# =============================================================================

set -Eeuo pipefail

# =============================================================================
# Color Definitions & Styling
# =============================================================================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'
WHITE='\033[1;37m'; BOLD='\033[1m'; DIM='\033[2m'
RESET='\033[0m'; BG_BLUE='\033[44m'; BG_GREEN='\033[42m'

# =============================================================================
# Global Variables
# =============================================================================
SCRIPT_VERSION="2.0"
CONFIG_DIR="/tmp/arch_installer_$(date +%s)"
LOG_FILE="${CONFIG_DIR}/install.log"
CONFIG_FILE="${CONFIG_DIR}/config.json"
declare -A CONFIG
MENU_CHOICE=0
SELECTED_WIRELESS_INTERFACE=""
CURRENT_STEP="startup"

# =============================================================================
# Utility Functions
# =============================================================================
print_header() {
    clear
    echo -e "${BG_BLUE}${WHITE}${BOLD}================================================================${RESET}"
    echo -e "${BG_BLUE}${WHITE}${BOLD}       Arch Linux Ultimate Installer v${SCRIPT_VERSION}                  ${RESET}"
    echo -e "${BG_BLUE}${WHITE}${BOLD}================================================================${RESET}"
    echo
}

print_section() {
    echo -e "\n${CYAN}${BOLD}▶ $1${RESET}"
    echo -e "${CYAN}────────────────────────────────────────────────────────────────${RESET}"
}

info()    { echo -e "${CYAN}[INFO]${RESET}  $*" | tee -a "$LOG_FILE"; }
success() { echo -e "${GREEN}[✓]${RESET}    $*" | tee -a "$LOG_FILE"; }
warn()    { echo -e "${YELLOW}[!]${RESET}   $*" | tee -a "$LOG_FILE"; }
error()   { echo -e "${RED}[✗]${RESET}   $*" | tee -a "$LOG_FILE" >&2; }

set_step() {
    CURRENT_STEP="$1"
    info "Step: $CURRENT_STEP"
}

print_log_tail() {
    if [[ -f "$LOG_FILE" ]]; then
        echo -e "\n${YELLOW}${BOLD}Last log lines:${RESET}" >&2
        tail -n 40 "$LOG_FILE" >&2 || true
    fi
}

fatal_error() {
    local exit_code=${1:-1}
    local line_no=${2:-unknown}
    local failed_command=${3:-unknown}

    set +e
    echo >&2
    error "Installation failed during step: $CURRENT_STEP"
    error "Line: $line_no"
    error "Command: $failed_command"
    error "Exit code: $exit_code"
    print_log_tail

    echo >&2
    warn "Recovery hints:"
    warn "  - Check mounts with: findmnt /mnt"
    warn "  - Check disks with: lsblk -f"
    warn "  - Unmount before retry with: umount -R /mnt 2>/dev/null; swapoff -a"
    warn "  - Full log: $LOG_FILE"
    exit "$exit_code"
}

show_progress() {
    local pid=$1
    local message=$2
    local delay=0.1
    local spinstr='|/-\'
    local status

    echo -ne "${CYAN}[INFO]${RESET}  ${message}... "
    while kill -0 $pid 2>/dev/null; do
        local temp=${spinstr#?}
        printf "[%c]" "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b"
    done

    set +e
    wait "$pid"
    status=$?
    set -e

    if [ "$status" -eq 0 ]; then
        echo -e "${GREEN}Done!${RESET}"
    else
        echo -e "${RED}Failed!${RESET}"
    fi

    return "$status"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root!"
        exit 1
    fi
}

internet_available() {
    ping -c 1 -W 5 archlinux.org &>/dev/null
}

get_wireless_interfaces() {
    local iface

    for iface in /sys/class/net/*; do
        [[ -d "$iface/wireless" ]] && basename "$iface"
    done

    if command -v iw &>/dev/null; then
        iw dev 2>/dev/null | awk '/Interface/ {print $2}'
    fi
}

select_wireless_interface() {
    local interfaces=()
    local options=()

    mapfile -t interfaces < <(get_wireless_interfaces | awk 'NF && !seen[$0]++')

    if [ ${#interfaces[@]} -eq 0 ]; then
        error "No wireless network interface found."
        return 1
    fi

    if [ ${#interfaces[@]} -eq 1 ]; then
        SELECTED_WIRELESS_INTERFACE="${interfaces[0]}"
        return 0
    fi

    for iface in "${interfaces[@]}"; do
        options+=("$iface" "Wireless interface")
    done

    show_menu "Select wireless interface:" "${options[@]}"
    SELECTED_WIRELESS_INTERFACE="${interfaces[$((MENU_CHOICE-1))]}"
}

connect_wifi_nmcli() {
    local iface=$1
    local networks=()
    local options=()
    local network ssid password

    systemctl start NetworkManager &>/dev/null || true
    info "Scanning Wi-Fi networks with NetworkManager..."

    mapfile -t networks < <(
        nmcli -t --escape no -f SSID,SIGNAL dev wifi list ifname "$iface" --rescan yes 2>/dev/null |
            awk -F: '$1 != "" && !seen[$1]++ {print $1 "|" $2}'
    )

    if [ ${#networks[@]} -eq 0 ]; then
        warn "No Wi-Fi networks found by NetworkManager."
        return 1
    fi

    for network in "${networks[@]}"; do
        options+=("${network%%|*}" "Signal: ${network##*|}%")
    done
    options+=("Enter SSID manually" "Use this for hidden networks")

    show_menu "Select Wi-Fi network:" "${options[@]}"
    local choice=$MENU_CHOICE

    if [ "$choice" -eq "$((${#networks[@]} + 1))" ]; then
        read -rp "SSID: " ssid
    else
        ssid="${networks[$((choice-1))]%%|*}"
    fi

    read -rsp "Wi-Fi password (leave empty for open network): " password
    echo

    if [[ -n "$password" ]]; then
        nmcli dev wifi connect "$ssid" password "$password" ifname "$iface"
    else
        nmcli dev wifi connect "$ssid" ifname "$iface"
    fi
}

connect_wifi_iwctl() {
    local iface=$1
    local networks=()
    local options=()
    local ssid password

    if ! command -v iwctl &>/dev/null; then
        error "iwctl is not available. Please connect manually or install iwd/NetworkManager."
        return 1
    fi

    systemctl start iwd &>/dev/null || true
    rfkill unblock wifi &>/dev/null || true

    info "Scanning Wi-Fi networks with iwd..."
    iwctl station "$iface" scan
    sleep 3

    mapfile -t networks < <(
        iwctl station "$iface" get-networks |
            sed -E 's/\x1B\[[0-9;]*[mK]//g' |
            awk '
                NR > 4 {
                    line=$0
                    sub(/^[[:space:]>]*/, "", line)
                    sub(/[[:space:]]+(open|psk|8021x|wep)[[:space:]].*/, "", line)
                    sub(/[[:space:]]+$/, "", line)
                    if (line != "" && line != "Network name" && !seen[line]++) print line
                }
            '
    )

    if [ ${#networks[@]} -eq 0 ]; then
        warn "No Wi-Fi networks found by iwd."
        read -rp "SSID: " ssid
    else
        for ssid in "${networks[@]}"; do
            options+=("$ssid" "Available Wi-Fi network")
        done
        options+=("Enter SSID manually" "Use this for hidden networks")

        show_menu "Select Wi-Fi network:" "${options[@]}"
        local choice=$MENU_CHOICE

        if [ "$choice" -eq "$((${#networks[@]} + 1))" ]; then
            read -rp "SSID: " ssid
        else
            ssid="${networks[$((choice-1))]}"
        fi
    fi

    read -rsp "Wi-Fi password (leave empty for open network): " password
    echo

    if [[ -n "$password" ]]; then
        iwctl --passphrase "$password" station "$iface" connect "$ssid"
    else
        iwctl station "$iface" connect "$ssid"
    fi
}

connect_wifi() {
    print_section "Wi-Fi Connection"

    local iface
    select_wireless_interface || return 1
    iface="$SELECTED_WIRELESS_INTERFACE"
    info "Selected wireless interface: $iface"

    if command -v nmcli &>/dev/null; then
        connect_wifi_nmcli "$iface" || connect_wifi_iwctl "$iface"
    else
        connect_wifi_iwctl "$iface"
    fi

    info "Waiting for network connection..."
    sleep 5
    internet_available
}

check_internet() {
    info "Checking internet connectivity..."
    if ! internet_available; then
        warn "No internet connection detected."
        echo -ne "${YELLOW}Connect to Wi-Fi now? (yes/no): ${RESET}"
        read -r wifi_choice

        if [[ "$wifi_choice" =~ ^([Yy]|yes|YES|نعم|اي|إي)$ ]]; then
            if ! connect_wifi; then
                error "Wi-Fi connection failed or internet is still unavailable."
                exit 1
            fi
        else
            error "No internet connection. Please connect first."
            exit 1
        fi
    fi
    success "Internet connection OK"
}

check_uefi() {
    if [[ -d /sys/firmware/efi ]]; then
        CONFIG["boot_mode"]="uefi"
        success "UEFI boot mode detected"
    else
        CONFIG["boot_mode"]="bios"
        warn "Legacy BIOS boot mode detected"
    fi
}

init_environment() {
    mkdir -p "$CONFIG_DIR"
    touch "$LOG_FILE"
    info "Installation log: $LOG_FILE"
}

require_commands() {
    local missing=()
    local commands=(
        arch-chroot awk basename genfstab grep lsblk lspci mount pacman
        pacstrap parted ping sed systemctl tail tee mkfs.ext4 mkfs.xfs mkfs.btrfs mountpoint
        partprobe pvcreate vgcreate lvcreate
    )

    if [[ "${CONFIG["boot_mode"]:-}" == "uefi" ]]; then
        commands+=(mkfs.fat)
    fi

    for cmd in "${commands[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        error "Missing required commands: ${missing[*]}"
        exit 1
    fi
}

partition_name() {
    local disk=$1
    local number=$2

    if [[ "$disk" =~ [0-9]$ ]]; then
        echo "${disk}p${number}"
    else
        echo "${disk}${number}"
    fi
}

prepare_mountpoint() {
    set_step "mountpoint preparation"

    if mountpoint -q /mnt; then
        warn "/mnt is already mounted."
        echo -ne "${YELLOW}Unmount /mnt before continuing? (yes/no): ${RESET}"
        read -r unmount_choice

        if [[ "$unmount_choice" == "yes" ]]; then
            umount -R /mnt
            swapoff -a || true
            success "/mnt unmounted"
        else
            error "Cannot continue safely while /mnt is already mounted."
            exit 1
        fi
    fi
}

# =============================================================================
# Menu System
# =============================================================================
show_menu() {
    local title=$1
    shift
    local options=("$@")
    local choice
    
    echo -e "\n${BOLD}${title}${RESET}"
    echo -e "${DIM}────────────────────────────────────────────────────────────────${RESET}"
    
    for i in "${!options[@]}"; do
        if (( i % 2 == 0 )); then
            printf "${GREEN}%2d)${RESET} %-30s" "$((i/2+1))" "${options[$i]}"
        else
            printf "${GREEN}%2d)${RESET} %-30s\n" "$((i/2+1))" "${options[$i]}"
        fi
    done
    
    echo -e "${DIM}────────────────────────────────────────────────────────────────${RESET}"
    echo -ne "${YELLOW}Enter your choice [1-$((${#options[@]}/2))]: ${RESET}"
    read -r choice
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$((${#options[@]}/2))" ]; then
        MENU_CHOICE=$choice
        return 0
    else
        warn "Invalid choice. Please try again."
        show_menu "$title" "${options[@]}"
    fi
}

# =============================================================================
# Update Mirrors
# =============================================================================
select_mirror_strategy() {
    print_section "Pacman Mirror Strategy"

    show_menu "Choose mirror handling:" \
        "Skip mirror update" "Use current Arch ISO mirrorlist" \
        "Fast mirror update" "Rate a small set of recent HTTPS mirrors" \
        "Full mirror update" "Rate more mirrors, slower but broader"

    case $MENU_CHOICE in
        1) CONFIG["mirror_mode"]="skip";;
        2) CONFIG["mirror_mode"]="fast";;
        3) CONFIG["mirror_mode"]="full";;
    esac
}

update_mirrors() {
    set_step "mirror optimization"
    print_section "Optimizing Pacman Mirrors"
    local status=0
    local mirror_backup="/etc/pacman.d/mirrorlist.bak.$(date +%s)"

    if [[ "${CONFIG["mirror_mode"]:-fast}" == "skip" ]]; then
        warn "Skipping mirror optimization."
        return 0
    fi

    info "Downloading and sorting mirrors by speed..."
    
    if ! command -v reflector &>/dev/null; then
        set +e
        pacman -Sy --noconfirm reflector 2>&1 | tee -a "$LOG_FILE"
        status=${PIPESTATUS[0]}
        set -e

        if [ "$status" -ne 0 ]; then
            warn "Could not install reflector; continuing with the current mirrorlist."
            return 0
        fi
    fi

    if [[ -f /etc/pacman.d/mirrorlist ]]; then
        cp /etc/pacman.d/mirrorlist "$mirror_backup"
        info "Mirrorlist backup created: $mirror_backup"
    fi

    set +e
    if [[ "${CONFIG["mirror_mode"]:-fast}" == "full" ]]; then
        reflector --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist 2>&1 | tee -a "$LOG_FILE"
    else
        reflector --latest 8 --protocol https --sort rate --save /etc/pacman.d/mirrorlist 2>&1 | tee -a "$LOG_FILE"
    fi
    status=${PIPESTATUS[0]}
    set -e

    if [ "$status" -eq 0 ]; then
        success "Mirrors updated successfully"
    else
        warn "Mirror optimization failed; continuing with the current mirrorlist."
        if [[ -f "$mirror_backup" ]]; then
            cp "$mirror_backup" /etc/pacman.d/mirrorlist
            warn "Restored mirrorlist backup."
        fi
    fi
}

# =============================================================================
# Installation Profiles
# =============================================================================
select_profile() {
    set_step "profile selection"
    print_header
    print_section "Installation Profile Selection"
    
    show_menu "Choose your installation type:" \
        "Minimal Base System" "Bare system with essential tools only" \
        "Desktop Environment" "Full desktop with GUI applications" \
        "Server Configuration" "Server-optimized with Docker, SSH, etc." \
        "Developer Workstation" "Development tools and environments" \
        "Gaming Setup" "Gaming-optimized with Steam, Wine, etc." \
        "Custom Installation" "Choose everything manually"
    
    local choice=$MENU_CHOICE
    case $choice in
        1) CONFIG["profile"]="minimal";;
        2) CONFIG["profile"]="desktop";;
        3) CONFIG["profile"]="server";;
        4) CONFIG["profile"]="developer";;
        5) CONFIG["profile"]="gaming";;
        6) CONFIG["profile"]="custom";;
    esac
    
    success "Selected profile: ${CONFIG["profile"]}"
}

# =============================================================================
# Desktop Environment Selection
# =============================================================================
select_desktop() {
    set_step "desktop selection"
    if [[ "${CONFIG["profile"]}" == "server" || "${CONFIG["profile"]}" == "minimal" ]]; then
        CONFIG["desktop"]="none"
        return 0
    fi
    
    print_header
    print_section "Desktop Environment / Window Manager"
    
    local de_options=(
        "KDE Plasma (Full)" "Complete KDE Plasma desktop"
        "KDE Plasma (Minimal)" "Lightweight KDE Plasma"
        "GNOME (Full)" "Complete GNOME desktop"
        "GNOME (Minimal)" "GNOME without extra apps"
        "XFCE4" "Lightweight traditional desktop"
        "i3 Window Manager" "Tiling window manager"
        "Sway (Wayland)" "Modern Wayland compositor"
        "Hyprland" "Dynamic tiling Wayland compositor"
        "No Desktop" "Command-line only"
    )
    
    if [[ "${CONFIG["profile"]}" == "gaming" ]]; then
        de_options+=("Gamescope" "Steam Deck-like gaming session")
    fi
    
    show_menu "Select your desktop environment:" "${de_options[@]}"
    local choice=$MENU_CHOICE
    
    case $choice in
        1) CONFIG["desktop"]="kde-full";;
        2) CONFIG["desktop"]="kde-minimal";;
        3) CONFIG["desktop"]="gnome-full";;
        4) CONFIG["desktop"]="gnome-minimal";;
        5) CONFIG["desktop"]="xfce4";;
        6) CONFIG["desktop"]="i3";;
        7) CONFIG["desktop"]="sway";;
        8) CONFIG["desktop"]="hyprland";;
        9) CONFIG["desktop"]="none";;
        10) CONFIG["desktop"]="gamescope";;
    esac
}

# =============================================================================
# Advanced Partitioning System
# =============================================================================
select_filesystem() {
    set_step "filesystem selection"
    print_section "Filesystem Selection"

    show_menu "Choose root filesystem:" \
        "ext4" "Stable default filesystem" \
        "btrfs" "Subvolumes for snapshots and rollback workflows" \
        "xfs" "High-performance filesystem for large files"

    case $MENU_CHOICE in
        1) CONFIG["filesystem"]="ext4";;
        2) CONFIG["filesystem"]="btrfs";;
        3) CONFIG["filesystem"]="xfs";;
    esac
}

detect_disks() {
    set_step "disk detection"
    print_section "Storage Device Detection"
    info "Detecting available storage devices..."
    
    local disks=()
    while IFS= read -r line; do
        local disk_name=$(echo "$line" | awk '{print $1}')
        local disk_size=$(echo "$line" | awk '{print $2}')
        local disk_model=$(echo "$line" | awk '{print $3" "$4" "$5}')
        disks+=("$disk_name" "$disk_size - $disk_model")
    done < <(lsblk -d -o NAME,SIZE,MODEL | grep -v "loop" | tail -n +2)
    
    if [ ${#disks[@]} -eq 0 ]; then
        error "No storage devices found!"
        exit 1
    fi
    
    show_menu "Select target disk:" "${disks[@]}"
    local disk_index=$(((MENU_CHOICE-1)*2))
    CONFIG["target_disk"]="/dev/${disks[$disk_index]}"
    
    warn "WARNING: ALL DATA ON ${CONFIG["target_disk"]} WILL BE DESTROYED!"
    echo -ne "${RED}Type 'YES' to confirm: ${RESET}"
    read -r confirm
    if [[ "$confirm" != "YES" ]]; then
        info "Installation cancelled."
        exit 0
    fi
}

partition_disk() {
    set_step "partitioning"
    print_header
    print_section "Partitioning Strategy"
    
    show_menu "Choose partitioning method:" \
        "Automatic (Simple)" "Automatic partitioning with ext4" \
        "Automatic (LVM)" "LVM with separate /home" \
        "Manual (cfdisk)" "Launch cfdisk for manual partitioning" \
        "Use Existing" "Use already mounted partitions"
    
    local choice=$MENU_CHOICE
    local disk="${CONFIG["target_disk"]}"
    
    case $choice in
        1) auto_partition_simple "$disk";;
        2) auto_partition_lvm "$disk";;
        3) manual_partition "$disk";;
        4) use_existing_partitions;;
    esac
}

auto_partition_simple() {
    set_step "automatic partitioning"
    local disk=$1
    info "Creating automatic partitions on ${disk}..."
    
    # Create GPT table
    parted -s "$disk" mklabel gpt
    
    if [[ "${CONFIG["boot_mode"]}" == "uefi" ]]; then
        # EFI partition
        parted -s "$disk" mkpart ESP fat32 1MiB 513MiB
        parted -s "$disk" set 1 esp on
        CONFIG["efi_part"]="$(partition_name "$disk" 1)"
        
        # Root partition
        parted -s "$disk" mkpart root 513MiB 100%
        CONFIG["root_part"]="$(partition_name "$disk" 2)"
    else
        # BIOS boot partition
        parted -s "$disk" mkpart primary 1MiB 2MiB
        parted -s "$disk" set 1 bios_grub on
        
        # Root partition
        parted -s "$disk" mkpart root 2MiB 100%
        CONFIG["root_part"]="$(partition_name "$disk" 2)"
    fi
    
    partprobe "$disk" || true
    sleep 2

    # Format and mount
    if [[ -n "${CONFIG["efi_part"]+x}" ]]; then
        mkfs.fat -F32 "${CONFIG["efi_part"]}"
    fi
    format_root_partition "${CONFIG["root_part"]}"
    mount_root_partition "${CONFIG["root_part"]}"
    
    success "Automatic partitioning complete"
}

auto_partition_lvm() {
    local disk=$1
    set_step "automatic LVM partitioning"
    info "Creating LVM layout on ${disk}..."

    parted -s "$disk" mklabel gpt

    if [[ "${CONFIG["boot_mode"]}" == "uefi" ]]; then
        parted -s "$disk" mkpart ESP fat32 1MiB 513MiB
        parted -s "$disk" set 1 esp on
        CONFIG["efi_part"]="$(partition_name "$disk" 1)"
        parted -s "$disk" mkpart lvm 513MiB 100%
        CONFIG["lvm_part"]="$(partition_name "$disk" 2)"
    else
        parted -s "$disk" mkpart primary 1MiB 2MiB
        parted -s "$disk" set 1 bios_grub on
        parted -s "$disk" mkpart lvm 2MiB 100%
        CONFIG["lvm_part"]="$(partition_name "$disk" 2)"
    fi

    partprobe "$disk" || true
    sleep 2

    if [[ -n "${CONFIG["efi_part"]+x}" ]]; then
        mkfs.fat -F32 "${CONFIG["efi_part"]}"
    fi

    pvcreate -ff -y "${CONFIG["lvm_part"]}"
    vgcreate vg0 "${CONFIG["lvm_part"]}"
    if [[ "${CONFIG["filesystem"]:-ext4}" == "btrfs" ]]; then
        lvcreate -l 100%FREE -n root vg0
    else
        lvcreate -L 40G -n root vg0
        lvcreate -l 100%FREE -n home vg0
        CONFIG["home_part"]="/dev/vg0/home"
    fi

    CONFIG["root_part"]="/dev/vg0/root"

    format_root_partition "${CONFIG["root_part"]}"
    if [[ -n "${CONFIG["home_part"]+x}" ]]; then
        format_data_partition "${CONFIG["home_part"]}"
    fi
    mount_root_partition "${CONFIG["root_part"]}"

    if [[ -n "${CONFIG["home_part"]+x}" && "${CONFIG["filesystem"]:-ext4}" != "btrfs" ]]; then
        mkdir -p /mnt/home
        mount "${CONFIG["home_part"]}" /mnt/home
    fi

    success "LVM partitioning complete"
}

manual_partition() {
    set_step "manual partitioning"
    local disk=$1
    info "Launching cfdisk for manual partitioning..."
    cfdisk "$disk"
    
    warn "After partitioning, specify your partitions:"
    if [[ "${CONFIG["boot_mode"]}" == "uefi" ]]; then
        read -rp "EFI partition (e.g., ${disk}1): " CONFIG["efi_part"]
    fi
    read -rp "Root partition (e.g., ${disk}2): " CONFIG["root_part"]
    read -rp "Home partition (optional, press Enter to skip): " CONFIG["home_part"]
    read -rp "Swap partition (optional, press Enter to skip): " CONFIG["swap_part"]
    
    format_and_mount_partitions
}

use_existing_partitions() {
    info "Using existing partitions..."
    warn "Please specify your already mounted partitions:"
    read -rp "Root partition: " CONFIG["root_part"]
    if [[ "${CONFIG["boot_mode"]}" == "uefi" ]]; then
        read -rp "EFI partition: " CONFIG["efi_part"]
    fi
    read -rp "Home partition (optional): " CONFIG["home_part"]
}

format_root_partition() {
    local part=$1

    case "${CONFIG["filesystem"]:-ext4}" in
        "btrfs")
            info "Formatting root partition as Btrfs: $part"
            mkfs.btrfs -f "$part"
            ;;
        "xfs")
            info "Formatting root partition as XFS: $part"
            mkfs.xfs -f "$part"
            ;;
        *)
            info "Formatting root partition as ext4: $part"
            mkfs.ext4 -F "$part"
            ;;
    esac
}

format_data_partition() {
    local part=$1

    case "${CONFIG["filesystem"]:-ext4}" in
        "btrfs")
            info "Formatting data partition as Btrfs: $part"
            mkfs.btrfs -f "$part"
            ;;
        "xfs")
            info "Formatting data partition as XFS: $part"
            mkfs.xfs -f "$part"
            ;;
        *)
            info "Formatting data partition as ext4: $part"
            mkfs.ext4 -F "$part"
            ;;
    esac
}

mount_root_partition() {
    local part=$1

    if [[ "${CONFIG["filesystem"]:-ext4}" == "btrfs" ]]; then
        mount "$part" /mnt
        btrfs subvolume create /mnt/@
        if [[ -z "${CONFIG["home_part"]:-}" ]]; then
            btrfs subvolume create /mnt/@home
        fi
        btrfs subvolume create /mnt/@snapshots
        umount /mnt

        mount -o noatime,compress=zstd,subvol=@ "$part" /mnt
        mkdir -p /mnt/home /mnt/.snapshots
        if [[ -z "${CONFIG["home_part"]:-}" ]]; then
            mount -o noatime,compress=zstd,subvol=@home "$part" /mnt/home
        fi
        mount -o noatime,compress=zstd,subvol=@snapshots "$part" /mnt/.snapshots
    else
        mount "$part" /mnt
    fi

    if [[ -n "${CONFIG["efi_part"]+x}" ]]; then
        mkdir -p /mnt/boot
        mount "${CONFIG["efi_part"]}" /mnt/boot
    fi
}

format_and_mount_partitions() {
    set_step "formatting and mounting"
    print_section "Formatting and Mounting"
    
    # Format EFI partition
    if [[ -n "${CONFIG["efi_part"]+x}" ]]; then
        info "Formatting EFI partition: ${CONFIG["efi_part"]}"
        mkfs.fat -F32 "${CONFIG["efi_part"]}"
    fi
    
    format_root_partition "${CONFIG["root_part"]}"
    
    # Format home partition if exists
    if [[ -n "${CONFIG["home_part"]+x}" ]] && [[ -n "${CONFIG["home_part"]}" ]]; then
        format_data_partition "${CONFIG["home_part"]}"
    fi
    
    mount_root_partition "${CONFIG["root_part"]}"
    
    if [[ -n "${CONFIG["home_part"]+x}" ]] && [[ -n "${CONFIG["home_part"]}" ]]; then
        mkdir -p /mnt/home
        mount "${CONFIG["home_part"]}" /mnt/home
    fi
    
    # Setup swap if exists
    if [[ -n "${CONFIG["swap_part"]+x}" ]] && [[ -n "${CONFIG["swap_part"]}" ]]; then
        mkswap "${CONFIG["swap_part"]}"
        swapon "${CONFIG["swap_part"]}"
    fi
    
    success "Partitions formatted and mounted"
}

# =============================================================================
# Package Selection
# =============================================================================
select_kernel() {
    set_step "kernel selection"
    print_section "Kernel Selection"
    
    show_menu "Choose kernel version:" \
        "linux" "Latest stable kernel" \
        "linux-lts" "Long-term support kernel" \
        "linux-zen" "Optimized for desktop/performance" \
        "linux-hardened" "Security-focused kernel"
    
    local choice=$MENU_CHOICE
    case $choice in
        1) CONFIG["kernel"]="linux";;
        2) CONFIG["kernel"]="linux-lts";;
        3) CONFIG["kernel"]="linux-zen";;
        4) CONFIG["kernel"]="linux-hardened";;
    esac
}

get_kernel_headers_package() {
    case "${CONFIG["kernel"]}" in
        "linux") echo "linux-headers";;
        "linux-lts") echo "linux-lts-headers";;
        "linux-zen") echo "linux-zen-headers";;
        "linux-hardened") echo "linux-hardened-headers";;
    esac
}

detect_gpu() {
    if lspci | grep -qi nvidia; then
        echo "nvidia"
    elif lspci | grep -Eqi "amd|radeon|ati"; then
        echo "amd"
    elif lspci | grep -qi "intel.*graphics\|vga.*intel"; then
        echo "intel"
    elif lspci | grep -Eqi "virtualbox|vmware|virtio"; then
        echo "virtual"
    else
        echo "unknown"
    fi
}

select_gpu_driver() {
    set_step "GPU driver selection"
    print_section "GPU Driver Selection"

    local detected
    detected=$(detect_gpu)
    CONFIG["gpu"]="auto"
    CONFIG["detected_gpu"]="$detected"

    show_menu "Choose GPU driver set (detected: $detected):" \
        "Auto" "Use detected GPU drivers" \
        "Intel" "Mesa, Vulkan Intel, media driver" \
        "AMD" "Mesa and Vulkan Radeon" \
        "NVIDIA Open DKMS" "nvidia-open-dkms with matching kernel headers" \
        "Virtual Machine" "Virtual guest graphics tools" \
        "None" "Do not add GPU-specific packages"

    case $MENU_CHOICE in
        1) CONFIG["gpu"]="$detected";;
        2) CONFIG["gpu"]="intel";;
        3) CONFIG["gpu"]="amd";;
        4) CONFIG["gpu"]="nvidia";;
        5) CONFIG["gpu"]="virtual";;
        6) CONFIG["gpu"]="none";;
    esac
}

get_gpu_packages() {
    local packages=()

    case "${CONFIG["gpu"]:-none}" in
        "intel")
            packages=("mesa" "vulkan-intel" "intel-media-driver" "libva-intel-driver")
            ;;
        "amd")
            packages=("mesa" "vulkan-radeon" "libva-mesa-driver" "mesa-vdpau")
            ;;
        "nvidia")
            packages=("nvidia-open-dkms" "nvidia-utils" "nvidia-settings" "dkms")
            ;;
        "virtual")
            packages=("mesa" "xf86-video-vmware" "virtualbox-guest-utils")
            ;;
    esac

    echo "${packages[@]}"
}

get_base_packages() {
    local packages=(
        "base" "${CONFIG["kernel"]}" "$(get_kernel_headers_package)" "linux-firmware"
        "base-devel" "git" "wget" "curl" "nano" "vim" "sudo"
        "networkmanager" "man-db" "man-pages" "texinfo" "lvm2"
    )
    
    # Add bootloader packages
    if [[ "${CONFIG["boot_mode"]}" == "uefi" ]]; then
        packages+=("grub" "efibootmgr")
    else
        packages+=("grub")
    fi
    
    # Add filesystem utilities
    packages+=("btrfs-progs" "xfsprogs" "dosfstools" "exfatprogs" "ntfs-3g")
    
    echo "${packages[@]}"
}

get_desktop_packages() {
    local packages=()
    
    case "${CONFIG["desktop"]}" in
        "kde-full")
            packages=("plasma-meta" "plasma-nm" "plasma-pa" "powerdevil"
                     "konsole" "dolphin" "kate" "okular" "gwenview"
                     "ark" "spectacle" "sddm" "sddm-kcm"
                     "pipewire" "pipewire-pulse" "pipewire-jack" "wireplumber"
                     "noto-fonts" "noto-fonts-cjk" "noto-fonts-emoji")
            ;;
        "kde-minimal")
            packages=("plasma-desktop" "plasma-nm" "plasma-pa" "powerdevil"
                     "konsole" "dolphin" "kate" "sddm"
                     "pipewire" "pipewire-pulse" "wireplumber"
                     "noto-fonts")
            ;;
        "gnome-full")
            packages=("gnome" "gnome-extra" "gdm"
                     "pipewire" "pipewire-pulse" "wireplumber"
                     "noto-fonts" "noto-fonts-cjk")
            ;;
        "gnome-minimal")
            packages=("gnome-shell" "gnome-terminal" "nautilus" "gdm"
                     "pipewire" "pipewire-pulse" "wireplumber"
                     "noto-fonts")
            ;;
        "xfce4")
            packages=("xfce4" "xfce4-goodies" "lightdm" "lightdm-gtk-greeter"
                     "pipewire" "pipewire-pulse" "wireplumber"
                     "noto-fonts" "thunar" "ristretto")
            ;;
        "i3")
            packages=("i3-wm" "i3status" "i3lock" "dmenu" "lightdm"
                     "rxvt-unicode" "feh" "picom"
                     "pipewire" "pipewire-pulse" "wireplumber"
                     "noto-fonts")
            ;;
        "sway")
            packages=("sway" "swaylock" "swayidle" "waybar" "wofi"
                     "foot" "mako" "grim" "slurp"
                     "pipewire" "pipewire-pulse" "wireplumber"
                     "noto-fonts")
            ;;
        "hyprland")
            packages=("hyprland" "waybar" "wofi" "foot" "mako"
                     "pipewire" "pipewire-pulse" "wireplumber"
                     "noto-fonts")
            ;;
        "gamescope")
            packages=("gamescope" "steam" "mangohud")
            ;;
    esac
    
    echo "${packages[@]}"
}

get_profile_packages() {
    local packages=()
    
    case "${CONFIG["profile"]}" in
        "server")
            packages=("openssh" "docker" "docker-compose" "nginx"
                     "certbot" "fail2ban" "ufw" "htop" "btop"
                     "tmux" "rsync" "cronie" "podman" "buildah")
            ;;
        "developer")
            packages=("python" "python-pip" "nodejs" "npm" "rust" "go"
                     "docker" "docker-compose" "git-lfs" "github-cli"
                     "postgresql" "redis" "sqlite" "neovim" "code"
                     "tmux" "zsh" "terminator")
            ;;
        "gaming")
            packages=("steam" "lutris" "wine" "wine-mono" "wine-gecko"
                     "gamemode" "mangohud" "goverlay" "heroic-games-launcher"
                     "mesa" "vulkan-radeon" "lib32-mesa" "vulkan-tools")
            ;;
    esac
    
    echo "${packages[@]}"
}

validate_packages() {
    set_step "package validation"
    print_section "Package Validation"

    local packages=("$@")
    local missing=()
    local pkg

    info "Refreshing package database..."
    pacman -Sy 2>&1 | tee -a "$LOG_FILE"

    info "Checking package availability before installation..."

    for pkg in "${packages[@]}"; do
        if ! pacman -Si "$pkg" &>/dev/null; then
            missing+=("$pkg")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        error "Package validation failed. Missing repository packages:"
        printf '  - %s\n' "${missing[@]}" >&2
        error "Move unavailable packages to post_install.sh or choose a smaller profile."
        exit 1
    fi

    success "All selected repository packages resolved successfully"
}

validate_selected_packages() {
    local packages=($(get_base_packages) $(get_desktop_packages) $(get_profile_packages) $(get_gpu_packages))
    validate_packages "${packages[@]}"
}

# =============================================================================
# User Configuration
# =============================================================================
validate_username() {
    local username=$1
    [[ "$username" =~ ^[a-z_][a-z0-9_-]*$ ]]
}

validate_hostname() {
    local hostname=$1
    [[ "$hostname" =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,62}$ && ! "$hostname" =~ -$ ]]
}

select_locale() {
    print_section "Locale Selection"

    show_menu "Choose system locale:" \
        "English only" "en_US.UTF-8" \
        "Arabic Iraq only" "ar_IQ.UTF-8" \
        "English + Arabic" "Generate both, keep English as default"

    case $MENU_CHOICE in
        1)
            CONFIG["locale_primary"]="en_US.UTF-8"
            CONFIG["locale_extra"]=""
            ;;
        2)
            CONFIG["locale_primary"]="ar_IQ.UTF-8"
            CONFIG["locale_extra"]=""
            ;;
        3)
            CONFIG["locale_primary"]="en_US.UTF-8"
            CONFIG["locale_extra"]="ar_IQ.UTF-8"
            ;;
    esac
}

configure_users() {
    set_step "user configuration"
    print_header
    print_section "User Configuration"
    
    while true; do
        read -rp "Username: " CONFIG["username"]
        if validate_username "${CONFIG["username"]}"; then
            break
        fi
        error "Invalid username. Use lowercase letters, numbers, underscore, or dash; start with a letter or underscore."
    done

    while true; do
        read -rsp "Password: " CONFIG["userpass"]
        echo
        read -rsp "Confirm password: " userpass2
        echo
        [[ "${CONFIG["userpass"]}" == "$userpass2" ]] && break
        error "Passwords don't match!"
    done
    
    read -rsp "Root password: " CONFIG["rootpass"]
    echo
    
    while true; do
        read -rp "Hostname: " CONFIG["hostname"]
        if validate_hostname "${CONFIG["hostname"]}"; then
            break
        fi
        error "Invalid hostname. Use letters, numbers, and dash; do not end with dash."
    done
    
    # Timezone selection
    print_section "Timezone Selection"
    show_menu "Select region:" \
        "Asia" "Asia region" \
        "Europe" "Europe region" \
        "America" "Americas region" \
        "Africa" "Africa region" \
        "Oceania" "Oceania region"
    
    local region=$MENU_CHOICE
    case $region in
        1) show_timezone_menu "Asia";;
        2) show_timezone_menu "Europe";;
        3) show_timezone_menu "America";;
        4) show_timezone_menu "Africa";;
        5) show_timezone_menu "Oceania";;
    esac

    select_locale
}

show_timezone_menu() {
    local region=$1
    local timezones=($(timedatectl list-timezones | grep "^${region}/" | sort))
    
    if [ ${#timezones[@]} -eq 0 ]; then
        warn "No timezones found for $region, using UTC"
        CONFIG["timezone"]="UTC"
        return
    fi
    
    local options=()
    for tz in "${timezones[@]}"; do
        options+=("$tz" "")
    done
    
    show_menu "Select timezone:" "${options[@]}"
    local choice=$MENU_CHOICE
    CONFIG["timezone"]="${timezones[$((choice-1))]}"
}

# =============================================================================
# Installation Process
# =============================================================================
install_system() {
    set_step "base system installation"
    print_section "Installing Base System"
    
    local packages=($(get_base_packages) $(get_desktop_packages) $(get_profile_packages) $(get_gpu_packages))
    local attempt status=0

    info "Installing ${#packages[@]} packages..."
    for attempt in 1 2; do
        info "pacstrap attempt $attempt/2"
        set +e
        pacstrap /mnt "${packages[@]}" 2>&1 | tee -a "$LOG_FILE"
        status=${PIPESTATUS[0]}
        set -e

        if [ "$status" -eq 0 ]; then
            success "Base packages installed"
            return 0
        fi

        warn "pacstrap failed on attempt $attempt."
        if [ "$attempt" -lt 2 ]; then
            warn "Retrying once in case this was a temporary mirror/network issue..."
            sleep 3
        fi
    done

    error "pacstrap failed after 2 attempts."
    return "$status"
}

generate_fstab() {
    set_step "fstab generation"
    print_section "Generating Filesystem Table"
    genfstab -U /mnt >> /mnt/etc/fstab
    success "fstab generated"
}

configure_system() {
    set_step "system configuration"
    print_section "Configuring System"
    local user_groups="wheel,audio,video,optical,storage"
    local locale_primary="${CONFIG["locale_primary"]:-en_US.UTF-8}"
    local locale_extra="${CONFIG["locale_extra"]:-}"

    if [[ "${CONFIG["profile"]}" == "server" || "${CONFIG["profile"]}" == "developer" ]]; then
        user_groups+=",docker"
    fi
    
    arch-chroot /mnt /bin/bash <<CHROOT
set -euo pipefail

# Timezone
ln -sf /usr/share/zoneinfo/${CONFIG["timezone"]} /etc/localtime
hwclock --systohc

# Locale
grep -q "^${locale_primary} UTF-8" /etc/locale.gen || echo "${locale_primary} UTF-8" >> /etc/locale.gen
if [[ -n "$locale_extra" ]]; then
    grep -q "^${locale_extra} UTF-8" /etc/locale.gen || echo "${locale_extra} UTF-8" >> /etc/locale.gen
fi
locale-gen
echo "LANG=${locale_primary}" > /etc/locale.conf

# Hostname
echo "${CONFIG["hostname"]}" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${CONFIG["hostname"]}.localdomain ${CONFIG["hostname"]}
EOF

# Users and passwords
echo "root:${CONFIG["rootpass"]}" | chpasswd
useradd -m -G "$user_groups" "${CONFIG["username"]}"
echo "${CONFIG["username"]}:${CONFIG["userpass"]}" | chpasswd

# Initramfs
if [[ -n "${CONFIG["lvm_part"]+x}" ]]; then
    sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block lvm2 filesystems fsck)/' /etc/mkinitcpio.conf
fi
mkinitcpio -P

# Sudoers
echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers.d/wheel

# Enable services
systemctl enable NetworkManager
case "${CONFIG["desktop"]}" in
    kde-*)
        systemctl enable sddm
        ;;
    gnome-*)
        systemctl enable gdm
        ;;
    xfce4)
        systemctl enable lightdm
        ;;
    i3)
        systemctl enable lightdm
        ;;
    *)
        ;;
esac

# Server-specific services
if [[ "${CONFIG["profile"]}" == "server" ]]; then
    systemctl enable sshd
    systemctl enable docker
    systemctl enable fail2ban
    systemctl enable ufw
fi

CHROOT
    success "System configured"
}

install_bootloader() {
    set_step "bootloader installation"
    print_section "Installing Bootloader"
    
    arch-chroot /mnt /bin/bash <<CHROOT
set -euo pipefail

if [[ "${CONFIG["boot_mode"]}" == "uefi" ]]; then
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
else
    grub-install --target=i386-pc ${CONFIG["target_disk"]}
fi

grub-mkconfig -o /boot/grub/grub.cfg
CHROOT
    success "Bootloader installed"
}

create_post_install_script() {
    set_step "post-install script creation"
    print_section "Creating Post-Installation Script"
    
    local post_script="/mnt/home/${CONFIG["username"]}/post_install.sh"
    
    cat > "$post_script" <<'POSTEOF'
#!/bin/bash
# Post-installation setup script

set -euo pipefail
GREEN='\033[0;32m'; CYAN='\033[0;36m'; RESET='\033[0m'

echo -e "${CYAN}Running post-installation setup...${RESET}"

# Install yay (AUR helper)
if ! command -v yay &>/dev/null; then
    echo "Installing yay..."
    git clone https://aur.archlinux.org/yay.git /tmp/yay
    cd /tmp/yay && makepkg -si --noconfirm
    cd ~
fi

POSTEOF
    
    # Add profile-specific post-install
    case "${CONFIG["profile"]}" in
        "server")
            cat >> "$post_script" <<'POSTEOF'
# Server hardening
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw enable

# Docker setup
sudo systemctl enable --now docker
sudo usermod -aG docker $USER

echo -e "${GREEN}Server setup complete!${RESET}"
POSTEOF
            ;;
        "developer")
            cat >> "$post_script" <<'POSTEOF'
# Install development tools from AUR
yay -S --noconfirm visual-studio-code-bin postman-bin insomnia-bin
echo -e "${GREEN}Developer setup complete!${RESET}"
POSTEOF
            ;;
    esac
    
    arch-chroot /mnt chown "${CONFIG["username"]}:${CONFIG["username"]}" "/home/${CONFIG["username"]}/post_install.sh"
    arch-chroot /mnt chmod +x "/home/${CONFIG["username"]}/post_install.sh"
    
    success "Post-installation script created"
}

# =============================================================================
# Main Installation Flow
# =============================================================================
main() {
    # Initial checks
    init_environment
    check_root
    print_header
    
    echo -e "${BOLD}Welcome to Arch Linux Ultimate Installer v${SCRIPT_VERSION}${RESET}"
    echo -e "${DIM}This tool will guide you through a complete Arch Linux installation.${RESET}"
    echo
    check_internet
    check_uefi
    require_commands
    
    # Update mirrors
    select_mirror_strategy
    update_mirrors
    
    # Configuration
    select_profile
    select_desktop
    select_kernel
    select_gpu_driver
    select_filesystem
    validate_selected_packages
    prepare_mountpoint
    detect_disks
    partition_disk
    configure_users
    
    # Summary and confirmation
    print_summary
    echo -ne "${RED}Start installation? (yes/no): ${RESET}"
    read -r confirm
    if [[ "$confirm" != "yes" ]]; then
        info "Installation cancelled."
        exit 0
    fi

    save_config
    
    # Execute installation
    install_system
    generate_fstab
    configure_system
    install_bootloader
    create_post_install_script
    
    # Cleanup
    print_section "Installation Complete"
    success "Arch Linux has been successfully installed!"
    echo
    echo -e "${GREEN}${BOLD}Next steps:${RESET}"
    echo -e "  1. Reboot and remove installation media"
    echo -e "  2. Login as ${BOLD}${CONFIG["username"]}${RESET}"
    echo -e "  3. Run ${BOLD}./post_install.sh${RESET} for additional setup"
    echo
    
    umount -R /mnt 2>/dev/null || true
    echo -ne "${YELLOW}Reboot now? (yes/no): ${RESET}"
    read -r reboot_choice
    if [[ "$reboot_choice" == "yes" ]]; then
        reboot
    fi
}

print_summary() {
    print_header
    print_section "Installation Summary"
    
    echo -e "${BOLD}Profile:${RESET}        ${GREEN}${CONFIG["profile"]}${RESET}"
    echo -e "${BOLD}Desktop:${RESET}        ${GREEN}${CONFIG["desktop"]:-"None"}${RESET}"
    echo -e "${BOLD}Kernel:${RESET}         ${GREEN}${CONFIG["kernel"]}${RESET}"
    echo -e "${BOLD}GPU:${RESET}            ${GREEN}${CONFIG["gpu"]:-"none"}${RESET}"
    echo -e "${BOLD}Filesystem:${RESET}     ${GREEN}${CONFIG["filesystem"]:-"ext4"}${RESET}"
    echo -e "${BOLD}Mirrors:${RESET}        ${GREEN}${CONFIG["mirror_mode"]:-"fast"}${RESET}"
    echo -e "${BOLD}Boot Mode:${RESET}      ${GREEN}${CONFIG["boot_mode"]}${RESET}"
    echo -e "${BOLD}Target Disk:${RESET}    ${RED}${CONFIG["target_disk"]}${RESET}"
    echo -e "${BOLD}Username:${RESET}       ${GREEN}${CONFIG["username"]}${RESET}"
    echo -e "${BOLD}Hostname:${RESET}       ${GREEN}${CONFIG["hostname"]}${RESET}"
    echo -e "${BOLD}Timezone:${RESET}       ${GREEN}${CONFIG["timezone"]}${RESET}"
    echo -e "${BOLD}Locale:${RESET}         ${GREEN}${CONFIG["locale_primary"]:-"en_US.UTF-8"}${RESET}"
    echo
}

save_config() {
    echo "{" > "$CONFIG_FILE"
    for key in "${!CONFIG[@]}"; do
        if [[ "$key" == "userpass" || "$key" == "rootpass" ]]; then
            continue
        fi
        echo "  \"$key\": \"${CONFIG[$key]}\"," >> "$CONFIG_FILE"
    done
    sed -i '$ s/,$//' "$CONFIG_FILE"
    echo "}" >> "$CONFIG_FILE"
    success "Configuration saved to: $CONFIG_FILE"
}

# =============================================================================
# Error Handling
# =============================================================================
trap 'fatal_error "$?" "$LINENO" "$BASH_COMMAND"' ERR

# =============================================================================
# Execute
# =============================================================================
main "$@"
