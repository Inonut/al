#!/bin/bash
set -e

source al_lib.sh

DEVICES=$(device_list)
IFS=' ' read -r -a DEVICES <<<"$DEVICES"

DEVICE="${DEVICES[0]}"
BOOT_MOUNT="/boot/efi"
SWAP_SIZE="4192"
REFLECTOR_COUNTRIES=(Romania Ukraine Spain)
ROOT_PASSWORD="archlinux"
ADMIN_NAME="admin"
ADMIN_PASS="admin"
TIMEZONE="/usr/share/zoneinfo/Europe/Bucharest"
PACKAGES=(nano zip unzip wget bash-completion)


init_log /var/log/al.log
set -x
save_function build_inline_script build_inline_script_old
function build_inline_script() {
  echo "set -x"
  build_inline_script_old "$@"
}

arch_linux_prepare_installation

arch_linux_wipe_partition "$DEVICE"
PARTITION_BOOT=$(arch_linux_create_boot_partition "$DEVICE")
PARTITION_ROOT=$(arch_linux_create_root_partition "$DEVICE")
arch_linux_format_boot_partition "$PARTITION_BOOT"
arch_linux_format_root_partition "$PARTITION_ROOT"
arch_linux_mount_root_partition "$PARTITION_ROOT"
arch_linux_mount_boot_partition "$PARTITION_BOOT" "$BOOT_MOUNT"

refactor_mirror_list "${REFLECTOR_COUNTRIES[@]}"
arch_linux_install

function arch_linux_configuration() {
  arch_linux_general_configuration
  refactor_mirror_list "${REFLECTOR_COUNTRIES[@]}"
  configure_network
  configure_timezone "$TIMEZONE"
  configure_grub "$BOOT_MOUNT" "$DEVICE"
  configure_swap_file "$SWAP_SIZE"
  configure_hibernation_on_swap_file
  enable_trim_if_support "$DEVICE"
  root_password "$ROOT_PASSWORD"
  configure_admin_user "$ADMIN_NAME" "$ADMIN_PASS"

  configure_needed_for_running_in_vm

  user_chroot_hook install_yay "$ADMIN_NAME"
  user_chroot "install_aur_packages ${PACKAGES[*]}" "$ADMIN_NAME"
  user_chroot_hook install_gnome "$ADMIN_NAME"
}

arch_linux_chroot arch_linux_configuration

cp /var/log/al.log /mnt/var/log/al.log
reboot
