#!/usr/bin/env bash
set -e

DEFAULT_OPTIONS='
# Used for Arch Linux Installer
DEVICE="/dev/sda"
SWAP_SIZE="4096"
HOSTNAME="archlinux"
ROOT_PASSWORD="archlinux"
USER_NAME="admin"
USER_PASSWORD="admin"
BOOT_MOUNT="/boot/efi"

# Used when log is enabled
LOG_FILE="al.log"

# Other variables generated by script will be store here
'

USAGE='

Script for installing Arch Linux and configure applications

options:
    --help                Show this help text
    --generate-defaults   Generate file al.conf
    --install-arch-uefi   Install Arch Linux in uefi mode, this erase all of your data
    --all-packages        Install all available packages
    --yay                 Install yay, tool for installing packages from AUR
    --ssh                 Configure ssh
    --gnome               Install gnome as user interface
    --chrome              Install Google Chrome

'

function read_variables() {
  local VARIABLE_LIST=("$@")
  if [[ -f al.conf ]]; then
    while IFS= read -r line; do
      if [[ -n "$line" ]]; then
        local var
        var=$(echo "$line" | awk -v FS='(|=)' '{print $1}')
        for i in "${!VARIABLE_LIST[@]}"; do
          if [[ "${VARIABLE_LIST[$i]}" == "$var" ]]; then
            unset "VARIABLE_LIST[$i]"
            eval "$line"
          fi
        done
      fi
    done < <(grep -v '^ *#' <al.conf)

    for i in "${!VARIABLE_LIST[@]}"; do
      read -p "${VARIABLE_LIST[$i]}=" "${VARIABLE_LIST[$i]}" &>/dev/tty
      echo "${VARIABLE_LIST[$i]}=${!VARIABLE_LIST[$i]}" >> al.conf
    done
  else
    echo "Generate defaults"
    generate_defaults
    read_variables "${VARIABLE_LIST[@]}"
  fi
}

function generate_defaults() {
  echo "$DEFAULT_OPTIONS" > al.conf
  echo "File al.conf was created!"
}

function init_log() {
  local LOG_FILE
  read_variables LOG_FILE
  rm -f "$LOG_FILE"
  exec 3>&1 4>&2
  trap 'exec 2>&4 1>&3' 0 1 2 3
  exec 1>"$LOG_FILE" 2>&1
}

function last_partition_name() {
  local DEVICE="$1"
  local last_partition
  local last_partition_tokens

  last_partition=$(fdisk "$DEVICE" -l | tail -1)
  IFS=" " read -r -a last_partition_tokens <<< "$last_partition"

  echo "${last_partition_tokens[0]}"
}

function last_partition_end_mb() {
  local DEVICE="$1"
  local last_partition
  local last_partition_tokens

  last_partition=$(parted "$DEVICE" unit MB print | tail -2)
  IFS=" " read -r -a last_partition_tokens <<< "$last_partition"
  if [[ "${last_partition_tokens[2]}" == *MB ]]; then
    echo "${last_partition_tokens[2]}"
  else
    echo "0%"
  fi
}

function install_arch_uefi() {
  local FEATURES=( "$@" )
  local SWAPFILE="/swapfile"
  local PARTITION_OPTIONS="defaults,noatime"
  local PARTITION_BOOT
  local PARTITION_ROOT
  local DEVICE
  local SWAP_SIZE
  local HOSTNAME
  local ROOT_PASSWORD
  local USER_NAME
  local USER_PASSWORD
  local BOOT_MOUNT
  read_variables DEVICE SWAP_SIZE HOSTNAME ROOT_PASSWORD USER_NAME USER_PASSWORD BOOT_MOUNT

  loadkeys us
  timedatectl set-ntp true

  # only on ping -c 1, packer gets stuck if -c 5
  local ping
  ping=$(ping -c 1 -i 2 -W 5 -w 30 "mirrors.kernel.org")
  if [[ "$ping" == 0 ]]; then
    echo "Network ping check failed. Cannot continue."
    exit
  fi

  sgdisk --zap-all "$DEVICE"
  wipefs -a "$DEVICE"

  parted "$DEVICE" mklabel gpt
  parted "$DEVICE" mkpart primary 0% 512MiB
  parted "$DEVICE" set 1 boot on
  parted "$DEVICE" set 1 esp on # this flag identifies a UEFI System Partition. On GPT it is an alias for boot.
  PARTITION_BOOT=$(last_partition_name "$DEVICE")
  parted "$DEVICE" mkpart primary 512MiB 100%
  PARTITION_ROOT=$(last_partition_name "$DEVICE")

  mkfs.fat -n ESP -F32 "$PARTITION_BOOT"
  mkfs.ext4 -L root "$PARTITION_ROOT"

  mount -o $PARTITION_OPTIONS "$PARTITION_ROOT" /mnt
  mkdir -p /mnt"$BOOT_MOUNT"
  mount -o $PARTITION_OPTIONS $PARTITION_BOOT /mnt"$BOOT_MOUNT"

  dd if=/dev/zero of=/mnt"$SWAPFILE" bs=1M count="$SWAP_SIZE" status=progress
  chmod 600 /mnt"$SWAPFILE"
  mkswap /mnt"$SWAPFILE"

  pacman -Sy --noconfirm reflector
  reflector --country 'Romania' --latest 25 --age 24 --protocol https --completion-percent 100 --sort rate --save /etc/pacman.d/mirrorlist

  VIRTUALBOX=""
  if lspci | grep -q -i virtualbox; then
    VIRTUALBOX=(virtualbox-guest-utils virtualbox-guest-dkms intel-ucode)
  fi
  pacstrap /mnt base base-devel linux linux-headers networkmanager efibootmgr grub "${VIRTUALBOX[@]}"

  {
    echo "[multilib]"
    echo "Include = /etc/pacman.d/mirrorlist"
  } >> /mnt/etc/pacman.conf
  arch-chroot /mnt pacman -Sy

  {
    genfstab -U /mnt
    echo "# swap"
    echo "$SWAPFILE none swap defaults 0 0"
    echo ""
  } >> /mnt/etc/fstab

  arch-chroot /mnt systemctl enable fstrim.timer

  arch-chroot /mnt ln -s -f /usr/share/zoneinfo/Europe/Bucharest /etc/localtime
  arch-chroot /mnt hwclock --systohc
  sed -i "s/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/" /mnt/etc/locale.gen
  arch-chroot /mnt locale-gen
  echo -e "LANG=en_US.UTF-8" >>/mnt/etc/locale.conf
  echo -e "KEYMAP=us" >/mnt/etc/vconsole.conf
  echo "$HOSTNAME" >/mnt/etc/hostname

  printf "%s\n%s\n" "$ROOT_PASSWORD" "$ROOT_PASSWORD" | arch-chroot /mnt passwd

  arch-chroot /mnt mkinitcpio -P

  arch-chroot /mnt systemctl enable NetworkManager.service

  arch-chroot /mnt useradd -m -G wheel,storage,optical -s /bin/bash "$USER_NAME"
  printf "%s\n%s\n" "$USER_PASSWORD" "$USER_PASSWORD" | arch-chroot /mnt passwd "$USER_NAME"
  sed -i "s/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/" /mnt/etc/sudoers

  sed -i 's/GRUB_DEFAULT=0/GRUB_DEFAULT=saved/' /mnt/etc/default/grub
  sed -i "s/#GRUB_SAVEDEFAULT=\"true\"/GRUB_SAVEDEFAULT=\"true\"/" /mnt/etc/default/grub
  arch-chroot /mnt grub-install --target=x86_64-efi --bootloader-id=grub --efi-directory="$BOOT_MOUNT" --recheck
  arch-chroot /mnt grub-mkconfig -o "/boot/grub/grub.cfg"
  if lspci | grep -q -i virtualbox; then
    echo -n "\EFI\grub\grubx64.efi" >"/mnt$BOOT_MOUNT/startup.nsh"
  fi

  mv al.sh /mnt/home/"$USER_NAME"
  mv al.conf /mnt/home/"$USER_NAME"
  sed -i 's/%wheel ALL=(ALL) ALL/%wheel ALL=(ALL) NOPASSWD: ALL/' /mnt/etc/sudoers
  arch-chroot /mnt bash -c "su $USER_NAME -c \"cd /home/$USER_NAME && ./al.sh ${FEATURES[*]}\""
  sed -i 's/%wheel ALL=(ALL) NOPASSWD: ALL/%wheel ALL=(ALL) ALL/' /mnt/etc/sudoers

  umount -R /mnt
}

function install_yay() {
  sudo pacman -S --noconfirm git
  git clone https://aur.archlinux.org/yay.git
  cd yay
  makepkg -si --noconfirm
  cd ..
  rm -rf yay
}

function install_ssh() {
  sudo pacman -S --noconfirm openssh
  sudo systemctl enable sshd.service
  sudo systemctl start sshd.service
}

function install_gnome() {
  if ! pacman -Q | grep yay; then
    install_yay
  fi

  yay -S --noconfirm gnome gnome-extra matcha-gtk-theme bash-completion xcursor-breeze papirus-maia-icon-theme-git noto-fonts ttf-hack gnome-shell-extensions gnome-shell-extension-topicons-plus
  sudo systemctl enable gdm.service
  sudo systemctl start gdm.service

  sudo mkdir -p /etc/init.d/
  cat <<EOT >> gnome-dconf
gsettings set org.gnome.desktop.interface cursor-theme 'Breeze'
gsettings set org.gnome.desktop.interface enable-animations true
gsettings set org.gnome.desktop.interface gtk-im-module 'gtk-im-context-simple'
gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark-Maia'
gsettings set org.gnome.desktop.interface document-font-name 'Sans 11'
gsettings set org.gnome.desktop.interface font-name 'Noto Sans 11'
gsettings set org.gnome.desktop.interface gtk-theme 'Matcha-azul'
gsettings set org.gnome.desktop.interface monospace-font-name 'Hack 10'
gsettings set org.gnome.nautilus.icon-view default-zoom-level 'small'
gsettings set org.gnome.Weather automatic-location true
gsettings set org.gnome.GWeather temperature-unit 'centigrade'
gsettings set org.gnome.desktop.peripherals.keyboard numlock-state true
gsettings set org.gnome.desktop.wm.preferences button-layout 'appmenu:minimize,maximize,close'
gsettings set org.gnome.gedit.preferences.editor scheme 'solarized-dark'
gsettings set org.gnome.gedit.preferences.editor use-default-font true
gsettings set org.gnome.gedit.preferences.editor wrap-last-split-mode 'word'
gsettings set org.gnome.shell disable-user-extensions false
gsettings set org.gnome.shell enabled-extensions "['TopIcons@phocean.net']"
gsettings set org.gnome.shell disabled-extensions "[]"
# gsettings set org.gnome.shell enabled-extensions ['user-theme@gnome-shell-extensions.gcampax.github.com']
gsettings set org.gnome.shell.extensions.user-theme name 'Matcha-dark-sea'

rm \$0
EOT

  chmod +x ./gnome-dconf
  if systemctl is-active --quiet dbus; then
    ./gnome-dconf
  else
    sudo mv gnome-dconf /etc/init.d/
  fi
}

function arguments_handler() {
  local ARGS=("$@")

  function remove_el_from_args() {
    for i in "${!ARGS[@]}"; do
      if [[ "${ARGS[$i]}" = "$1" ]]; then
        unset "ARGS[$i]"
      fi
    done
  }

  if [[ "${ARGS[*]}" =~ --log ]]; then
    remove_el_from_args --log
    init_log
  fi

  if [[ "${ARGS[*]}" =~ -v ]]; then
    remove_el_from_args -v
    set -x
  fi

  if [[ "${ARGS[*]}" =~ -h ]] || [[ "${ARGS[*]}" =~ --help ]]; then
    echo "$USAGE"
    exit 1
  fi

  if [[ "${ARGS[*]}" =~ --generate-defaults ]]; then
    echo "$DEFAULT_OPTIONS" > al.conf
    echo "File al.conf was created!"
    exit 1
  fi

  if [[ "${ARGS[*]}" =~ --install-arch-uefi ]]; then
    remove_el_from_args --install-arch-uefi
    install_arch_uefi "${ARGS[@]}"
  else
    if [[ "${ARGS[*]}" =~ --yay ]] || [[ "${ARGS[*]}" =~ --all-packages ]]; then
      remove_el_from_args --yay
      install_yay
    fi
    if [[ "${ARGS[*]}" =~ --ssh ]] || [[ "${ARGS[*]}" =~ --all-packages ]]; then
      remove_el_from_args --ssh
      install_ssh
    fi
    if [[ "${ARGS[*]}" =~ --gnome ]] || [[ "${ARGS[*]}" =~ --all-packages ]]; then
      remove_el_from_args --gnome
      install_gnome
    fi
  fi
}

function main() {
  local ARGS=("$@")
  arguments_handler "${ARGS[@]}"
}

main "$@"
