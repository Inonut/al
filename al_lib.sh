#!/bin/bash

set -e

###################
####>> TOOLS <<####
###################

function arr_contains_el() {
  local ARGS=("$@")
  local arg
  for ((arg = 1; arg < "${#ARGS[@]}"; arg++)); do
    if [[ "${ARGS[$arg]}" == "${ARGS[0]}" ]]; then
      return 0 # emit no error
    fi
  done

  return 1 # emit error
}

function checkpoint_variables() {
  IFS=' ' read -r -a INITIAL_VARIABLES <<<"$(compgen -v | tr "\n" " ")"
}

function collect_variables() {
  IFS=' ' read -r -a FINALE_VARIABLES <<<"$(compgen -v | tr "\n" " ")"

  local VARIABLE
  local var
  for var in "${FINALE_VARIABLES[@]}"; do
    if ! arr_contains_el "$var" "${INITIAL_VARIABLES[@]}" && [[ "$var" != INITIAL_VARIABLES ]]; then
      VARIABLE="
        $VARIABLE
        $(declare -p | pcregrep -M " $var=((\(.*\))|(\"((\n|.)*?)\"))")
      "
    fi
  done

  echo "$VARIABLE"
}

function device_list() {
  local DEVICES
  DEVICES=$(lsblk | grep disk | awk -v FS=' ' '{print "/dev/"$1}' | tr "\n" " ")
  echo "$DEVICES"
}

function init_log() {
  local LOG_FILE="$1"
  local dir
  dir=$(dirname "$LOG_FILE")
  mkdir -p "$dir"
  rm -f "$LOG_FILE"
  exec 1>"$LOG_FILE" 2>&1
}

function save_function() {
  local FN_NAME="$1"
  local NEW_FN_NAME="$2"
  local ORIG_FUNC
  ORIG_FUNC=$(declare -f "$FN_NAME")
  local NEW_NAME_FUNC="$NEW_FN_NAME${ORIG_FUNC#$FN_NAME}"
  eval "$NEW_NAME_FUNC"
}

function last_partition_name() {
  local DEVICE="$1"
  local last_partition
  local last_partition_tokens

  last_partition=$(fdisk "$DEVICE" -l | tail -1)
  IFS=" " read -r -a last_partition_tokens <<<"$last_partition"

  echo "${last_partition_tokens[0]}"
}

function last_partition_end_mb() {
  local DEVICE="$1"
  local last_partition
  local last_partition_tokens

  last_partition=$(parted "$DEVICE" unit MB print | tail -2)
  IFS=" " read -r -a last_partition_tokens <<<"$last_partition"
  if [[ "${last_partition_tokens[2]}" == *MB ]]; then
    echo "${last_partition_tokens[2]}"
  else
    echo "0%"
  fi
}

function last_partition_end_number_parted() {
  local DEVICE="$1"
  local LAST_PARTITION_NUMBER
  LAST_PARTITION_NUMBER=$(parted /dev/nvme0n1 print | awk '{if($1!="") a=$1} END {print a}')
  if [[ "$LAST_PARTITION_NUMBER" == '' ]]; then
    LAST_PARTITION_NUMBER='1'
  fi

  echo "$LAST_PARTITION_NUMBER"
}

function add_mb() {
  local a
  local b
  local c
  a=$(echo "$1" | awk -v FS='MB' '{print $1}')
  b=$(echo "$2" | awk -v FS='MB' '{print $1}')
  c=$(echo "$a + $b" | bs)
  echo "${c}MB"
}

function build_inline_script() {
  local FN
  IFS=' ' read -r -a FN <<<"$1"
  if [[ $(type -t "${FN[0]}") == "" ]]; then
    echo ""
    return 0
  fi
  local LIB_DIR=""
  if [[ -f $(dirname "$0")/al_lib.sh ]]; then
    LIB_DIR=$(dirname "$0")
  fi
  echo "
    $(cat "$LIB_DIR/al_lib.sh")

    $(collect_variables)
    $(type "${FN[0]}" | tail +2)
    $1
  "
}

###################
####<< TOOLS >>####
###################

function install_official_packages() {
  pacman -Sy --noconfirm "$@"
}

function install_aur_packages() {
  yay -Sy --noconfirm "$@"
}

function uninstall_aur_packages() {
  yay -Rs --noconfirm "$@"
}

function refactor_mirror_list() {
  local REFLECTOR_COUNTRIES=("$@")
  local COUNTRIES=()
  local COUNTRY
  for COUNTRY in "${REFLECTOR_COUNTRIES[@]}"; do
    COUNTRIES+=(--country "${COUNTRY}")
  done
  install_official_packages reflector
  reflector "${COUNTRIES[@]}" --latest 25 --age 24 --protocol https --completion-percent 100 --sort rate --save /etc/pacman.d/mirrorlist
}

function arch_linux_prepare_installation() {
  loadkeys us
  timedatectl set-ntp true

  # only on ping -c 1, packer gets stuck if -c 5
  local ping
  ping=$(ping -c 1 -i 2 -W 5 -w 30 "mirrors.kernel.org")
  if [[ "$ping" == 0 ]]; then
    echo "Network ping check failed. Cannot continue."
    exit 1
  fi
}

function arch_linux_wipe_partition() {
  local DEVICE="$1"

  sgdisk --zap-all "$DEVICE"
  wipefs -a "$DEVICE"

  if [ -d /sys/firmware/efi ]; then
    parted "$DEVICE" mklabel gpt
  else
    parted "$DEVICE" mklabel msdos
  fi
}

function arch_linux_create_next_partition() {
  local DEVICE="$1"
  local SIZE="$2"
  : "${SIZE:='100%'}"
  local LAST_MB
  local NEXT_SIZE

  LAST_MB=$(last_partition_end_mb "$DEVICE")
  if [[ "$LAST_MB" == 0% ]] || [[ "$SIZE" == 100% ]]; then
    NEXT_SIZE="$SIZE"
  else
    NEXT_SIZE=$(add_mb "$LAST_MB" "$SIZE")
  fi

  parted "$DEVICE" mkpart primary "$LAST_MB" "$NEXT_SIZE" >&2

  last_partition_name "$DEVICE"
}

function arch_linux_create_boot_partition() {
  local DEVICE="$1"
 # arch_linux_create_next_partition "$DEVICE" "512MB"



  local SIZE
  local LAST_MB
  local NEXT_SIZE
  local PARTITION_BOOT
  SIZE="512MB"

  LAST_MB=$(last_partition_end_mb "$DEVICE")
  if [[ "$LAST_MB" == 0% ]]; then
    NEXT_SIZE="$SIZE"
  else
    NEXT_SIZE=$(add_mb "$LAST_MB" "$SIZE")
  fi
  parted "$DEVICE" mkpart primary "$LAST_MB" "$NEXT_SIZE" >&2
  parted "$DEVICE" set 1 boot on >&2
  if [ -d /sys/firmware/efi ]; then
    parted "$DEVICE" set 1 esp on >&2
  fi
  PARTITION_BOOT=$(last_partition_name "$DEVICE")

  echo "$PARTITION_BOOT"
}

function arch_linux_create_root_partition() {
  local DEVICE="$1"
  local LAST_MB
  local PARTITION_BOOT

  LAST_MB=$(last_partition_end_mb "$DEVICE")
  parted "$DEVICE" mkpart primary "$LAST_MB" 100% >&2
  PARTITION_ROOT=$(last_partition_name "$DEVICE")

  echo "$PARTITION_ROOT"
}

function arch_linux_format_boot_partition() {
  local PARTITION_BOOT="$1"
  if [ -d /sys/firmware/efi ]; then
    mkfs.fat -n ESP -F32 "$PARTITION_BOOT"
  else
    mkfs.ext4 -L boot "$PARTITION_BOOT"
  fi
}

function arch_linux_format_root_partition() {
  local PARTITION_ROOT="$1"
  mkfs.ext4 -L root "$PARTITION_ROOT"
}

function arch_linux_mount_boot_partition() {
  local PARTITION_BOOT="$1"
  local BOOT_MOUNT="$2"

  mkdir -p /mnt"$BOOT_MOUNT"
  mount -o "defaults,noatime" "$PARTITION_BOOT" /mnt"$BOOT_MOUNT"
}

function arch_linux_mount_root_partition() {
  local PARTITION_ROOT="$1"

  mount -o "defaults,noatime" "$PARTITION_ROOT" /mnt
}

function arch_linux_install() {
  pacstrap /mnt base base-devel linux linux-headers linux-firmware

  genfstab -U /mnt >>/etc/fstab
}

function arch_linux_general_configuration() {
  local LOCALE="en_US.UTF-8 UTF-8"
  sed -i "s/#$LOCALE/$LOCALE/" /etc/locale.gen
  locale-gen
  echo -e "LANG=en_US.UTF-8" >>/etc/locale.conf
  echo -e "KEYMAP=us" >/etc/vconsole.conf

  {
    echo "[multilib]"
    echo "Include = /etc/pacman.d/mirrorlist"
  } >>/etc/pacman.conf
  sed -i 's/#Color/Color/' /etc/pacman.conf
  sed -i 's/#TotalDownload/TotalDownload/' /etc/pacman.conf

  sed -i "s/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/" /etc/sudoers

  cat <<EOT >>/etc/bash.bashrc
alias ll='ls -alF'
PS1='\[\033[01;32m\][\u@\h\[\033[01;37m\] \W\[\033[01;32m\]]\$\[\033[00m\] '
EOT
}

function enable_trim_if_support() {
  local DEVICE="$1"
  if ! lsblk "$DEVICE" --discard | grep -q 0B; then
    systemctl enable fstrim.timer
  fi
}

function configure_swap_file() {
  local SWAP_SIZE="$1"
  local SWAPFILE="$2"
  : "${SWAPFILE:=/swapfile}"

  dd if=/dev/zero of="$SWAPFILE" bs=1M count="$SWAP_SIZE" status=progress
  chmod 600 "$SWAPFILE"
  mkswap "$SWAPFILE"
  swapon "$SWAPFILE"

  {
    echo "# swap"
    echo "$SWAPFILE none swap defaults 0 0"
    echo ""
  } >>/etc/fstab

  mkdir -p /etc/sysctl.d
  echo 'vm.swappiness=10' >/etc/sysctl.d/99-swappiness.conf
}

function configure_network() {
  install_official_packages networkmanager
  systemctl enable NetworkManager.service
}

function root_password() {
  local ROOT_PASSWORD="$1"
  printf "%s\n%s\n" "$ROOT_PASSWORD" "$ROOT_PASSWORD" | passwd
}

function configure_timezone() {
  local TIMEZONE="$1"
  ln -s -f "$TIMEZONE" /etc/localtime
  hwclock --systohc
}

function configure_grub() {
  local BOOT_MOUNT="$1"
  local DEVICE="$2"
  install_official_packages grub
  sed -i 's/GRUB_DEFAULT=0/GRUB_DEFAULT=saved/' /etc/default/grub
  sed -i "s/#GRUB_SAVEDEFAULT=\"true\"/GRUB_SAVEDEFAULT=\"true\"/" /etc/default/grub
  if [ -d /sys/firmware/efi ]; then
    install_official_packages efibootmgr
    grub-install --target=x86_64-efi --bootloader-id=grub --efi-directory="$BOOT_MOUNT" --recheck
  else
    grub-install --target=i386-pc --recheck "$DEVICE"
  fi
  grub-mkconfig -o "/boot/grub/grub.cfg"
  if lspci | grep -q -i virtualbox; then
    echo -n "\EFI\grub\grubx64.efi" >"$BOOT_MOUNT/startup.nsh"
  fi
}

function arch_linux_chroot() {
  local RUN=""
  RUN=$(build_inline_script "$1")
  local LIB_DIR
  LIB_DIR=$(dirname "$0")
  cp "$LIB_DIR/al_lib.sh" /mnt/al_lib.sh
  echo "$RUN" >/mnt/run_arch_chroot.sh
  chmod +x /mnt/run_arch_chroot.sh
  arch-chroot /mnt bash /run_arch_chroot.sh
  rm -fr /mnt/run_arch_chroot.sh
  rm -fr /mnt/al_lib.sh
}

function user_chroot() {
  local RUNNING_USER="$2"
  if [[ "$RUNNING_USER" == '' ]]; then
    if [[ "$SUDO_USER" == '' ]]; then
      RUNNING_USER="$USER"
    else
      RUNNING_USER="$SUDO_USER"
    fi
  fi

  local RUN=""
  RUN=$(build_inline_script "$1")

  echo "$RUN" >/run_user.sh
  chmod +x /run_user.sh
  echo "$RUNNING_USER ALL=(ALL) NOPASSWD: ALL" >/etc/sudoers.d/10_"$RUNNING_USER"
  chmod +x /etc/sudoers.d/10_"$RUNNING_USER"
  su "$RUNNING_USER" -c "/run_user.sh"
  rm -fr /etc/sudoers.d/10_"$RUNNING_USER"
  rm -fr /run_user.sh
}

function user_chroot_hook() {
  local FN
  IFS=' ' read -r -a FN <<<"$1"
  local FN_NAME="${FN[0]}"
  unset "FN[0]"
  local FN_ARGS="${FN[*]}"

  if [[ $(type -t "${FN_NAME}_dep_system") == "function" ]]; then
    eval "${FN_NAME}_dep_system ${FN_ARGS}"
  fi
  if [[ $(type -t "${FN_NAME}_dep_user") == "function" ]]; then
    user_chroot "${FN_NAME}_dep_user ${FN_ARGS}" "$2"
  fi
  if [[ $(type -t "${FN_NAME}_conf_system") == "function" ]]; then
    eval "${FN_NAME}_conf_system ${FN_ARGS}"
  fi
  if [[ $(type -t "${FN_NAME}_conf_user") == "function" ]]; then
    user_chroot "${FN_NAME}_conf_user ${FN_ARGS}" "$2"
  fi
  if [[ $(type -t "${FN_NAME}") == "function" ]]; then
    user_chroot "${FN_NAME} ${FN_ARGS}" "$2"
  fi
}

function install_user_vagrant() {
  install_official_packages openssh

  local SSH_USERNAME="$1"
  local SSH_PASSWORD="$2"
  : "${SSH_USERNAME:=vagrant}"
  : "${SSH_PASSWORD:=vagrant}"

  local PASSWORD
  PASSWORD=$(openssl passwd -crypt "${SSH_PASSWORD}")

  # Vagrant-specific configuration
  useradd --password "${PASSWORD}" --comment 'Vagrant User' --create-home --user-group "${SSH_USERNAME}"
  echo "${SSH_USERNAME} ALL=(ALL) NOPASSWD: ALL" >>/etc/sudoers.d/10_"${SSH_USERNAME}"
  chmod +x /etc/sudoers.d/10_"${SSH_USERNAME}"

  systemctl enable sshd
  systemctl start sshd
}

function configure_admin_user() {
  local ADMIN_NAME="$1"
  local ADMIN_PASS="$2"
  : "${ADMIN_NAME:=admin}"
  : "${ADMIN_PASS:=admin}"
  useradd -m -G wheel,storage,optical -s /bin/bash "$ADMIN_NAME"
  printf "%s\n%s\n" "$ADMIN_PASS" "$ADMIN_PASS" | passwd "$ADMIN_NAME"

  sed -i 's/PS1=/#PS1=/g' "/home/$ADMIN_NAME/.bashrc"
}

function configure_needed_for_running_in_vm() {
  if lspci | grep -q -i virtualbox; then
    install_official_packages virtualbox-guest-utils virtualbox-guest-dkms
    install_user_vagrant vagrant vagrant
  fi
}

function install_yay_dep_system() {
  install_official_packages git
}

function install_yay_dep_user() {
  cd ~
  git clone https://aur.archlinux.org/yay-git.git
  cd yay-git
  makepkg -si --noconfirm
  cd ..
  rm -rf yay-git
}

function install_gnome_dep_user() {
  install_aur_packages gnome gnome-extra matcha-gtk-theme xcursor-breeze papirus-maia-icon-theme-git noto-fonts ttf-hack gnome-shell-extensions gnome-shell-extension-topicons-plus
  uninstall_aur_packages gnome-terminal
  install_aur_packages gnome-terminal-transparency
}

function install_gnome_conf_system() {
  systemctl enable gdm.service
  if ! systemctl is-active --quiet gdm; then
    systemctl start gdm.service
  fi

  mkdir -p /etc/dconf/profile
  cat <<'EOT' >/etc/dconf/profile/user
user-db:user
system-db:site
EOT

  mkdir -p /etc/dconf/db/site.d
  cat <<'EOT' >/etc/dconf/db/site.d/00_site_settings
[org/gnome/GWeather]
temperature-unit='centigrade'

[org/gnome/Weather]
automatic-location=true

[org/gnome/control-center]
last-panel='keyboard'

[org/gnome/desktop/interface]
cursor-theme='Breeze'
document-font-name='Sans 11'
enable-animations=true
font-name='Noto Sans 11'
gtk-im-module='gtk-im-context-simple'
gtk-theme='Matcha-azul'
icon-theme='Papirus-Dark-Maia'
monospace-font-name='Hack 10'

[org/gnome/desktop/peripherals/keyboard]
numlock-state=true

[org/gnome/desktop/wm/keybindings]
show-desktop=['<Super>d']
switch-applications=@as []
switch-applications-backward=@as []
switch-windows=['<Alt>Tab']
switch-windows-backward=['<Shift><Alt>Tab']

[org/gnome/desktop/wm/preferences]
button-layout='appmenu:minimize,maximize,close'

[org/gnome/gedit/preferences/editor]
scheme='solarized-dark'
use-default-font=true
wrap-last-split-mode='word'

[org/gnome/nautilus/icon-view]
default-zoom-level='small'

[org/gnome/settings-daemon/plugins/media-keys]
custom-keybindings=['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/']
home=['<Super>e']
www=['<Super>g']

[org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0]
binding='<Primary><Alt>t'
command='gnome-terminal'
name='terminal'

[org/gnome/shell]
disable-user-extensions=false
disabled-extensions=@as []
enabled-extensions=['TopIcons@phocean.net']

[org/gnome/shell/extensions/user-theme]
name='Matcha-dark-sea'

[org/gnome/shell/weather]
automatic-location=true

[org/gnome/shell/world-clocks]
locations=@av []

[org/gnome/system/location]
enabled=true

[org/gnome/terminal/legacy/profiles:]
default='c07cafa6-2725-4bc3-bc30-fda45a6eae8f'
list=['b1dcc9dd-5262-4d8d-a863-c897e6d979b9', 'c07cafa6-2725-4bc3-bc30-fda45a6eae8f']

[org/gnome/terminal/legacy/profiles:/:c07cafa6-2725-4bc3-bc30-fda45a6eae8f]
background-color='#2E3440'
background-transparency-percent=9
bold-color='#D8DEE9'
bold-color-same-as-fg=true
cursor-background-color='rgb(216,222,233)'
cursor-colors-set=true
cursor-foreground-color='rgb(59,66,82)'
default-size-columns=100
default-size-rows=27
foreground-color='#D8DEE9'
highlight-background-color='rgb(136,192,208)'
highlight-colors-set=true
highlight-foreground-color='rgb(46,52,64)'
nord-gnome-terminal-version='0.1.0'
palette=['#3B4252', '#BF616A', '#A3BE8C', '#EBCB8B', '#81A1C1', '#B48EAD', '#88C0D0', '#E5E9F0', '#4C566A', '#BF616A', '#A3BE8C', '#EBCB8B', '#81A1C1', '#B48EAD', '#8FBCBB', '#ECEFF4']
scrollbar-policy='never'
use-theme-background=false
use-theme-colors=false
use-theme-transparency=false
use-transparent-background=true
visible-name='Nord'

EOT

  if systemctl is-active --quiet dbus; then
    dconf update
  fi
}

function configure_hibernation_on_swap_file() {
  local SWAPFILE="$1"
  : "${SWAPFILE:=/swapfile}"
  local SWAP_DEVICE
  local SWAP_FILE_OFFSET

  SWAP_DEVICE=$(findmnt -no UUID -T "$SWAPFILE")
  SWAP_FILE_OFFSET=$(filefrag -v "$SWAPFILE" | awk '{ if($1=="0:"){print $4} }' | tr -d '.')
  eval "local $(< /etc/default/grub grep GRUB_CMDLINE_LINUX_DEFAULT)"
  GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT resume=$SWAP_DEVICE resume_offset=$SWAP_FILE_OFFSET"
  sed -i -E "s/GRUB_CMDLINE_LINUX_DEFAULT=.*$/GRUB_CMDLINE_LINUX_DEFAULT=\"$GRUB_CMDLINE_LINUX_DEFAULT\"/g" /etc/default/grub
  grub-mkconfig -o /boot/grub/grub.cfg
}

checkpoint_variables
