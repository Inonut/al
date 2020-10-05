#!/usr/bin/env bash

set -e

###################
####>> TOOLS <<####
###################

function arr_contains_el() {
  local ARGS=("$@")
  local arg
  for ((arg = 1; arg < "${#ARGS[@]}"; arg++)); do
    if [[ "${ARGS[$arg]}" == "$1" ]]; then
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
      VARIABLE+=$(declare -p | grep -e " $var=")"\n"
    fi
  done

  echo "$VARIABLE"
}

###################
####<< TOOLS >>####
###################






#function init_log() {
#  if args_contains_el archlinux; then
#    LOG_FILE="/mnt$LOG_FILE"
#  fi
#  local dir
#  dir=$(dirname "$LOG_FILE")
#  mkdir -p "$dir"
#  rm -f "$LOG_FILE"
#  exec 1>"$LOG_FILE" 2>&1
#}
#
#function init_verbose() {
#  set -x
#}
#
#function show_help() {
#  local DEVICES
#  DEVICES=$(device_list)
#  IFS=' ' read -r -a DEVICES <<<"$DEVICES"
#
#  echo -e "
#    This is a arch linux installer script. Also have some preconfigured packages.
#    You can use it with a configuration file \"al.conf\" or inline commands.
#    Command arguments override file arguments. If no value is provide then an error is shown.
#  "
#  echo -e "
#    Options:
#  "
#  column -t -s '|' <<<"
#            -v                                                                  | Verbose mode.
#            --log[=\"al.log\"]                                                  | Log all output into a LOG_FILE; If no value is provide default is '/var/log/al.log', (absolute path only)
#            --generate-config-template                                          | Generate an template with all possible options in './al.conf'
#  "
#  echo -e "
#    Preconfigured packages:
#  "
#  column -t -s '|' <<<"
#            * | archlinux[=\"$DEVICE\"]                                        | Install arch linux on device with defaults; This will wipe all of your data from device.
#              |                                                                | For more options use configuration file \"--generate-config-template\"
#              |                                                                | Available devices: (${DEVICES[*]})
#            * | admin-user[='$(print_array "${ADMIN_USER[@]}")']               | Add admin user; format: '(user pass)'
#            * | official-packages[='$(print_array "${OFFICIAL_PACKAGES[@]}")'] | Install official Arch Linux packages with pacman
#            * | aur-packages[='$(print_array "${AUR_PACKAGES[@]}")']           | Install aur Arch Linux packages with yay
#  "
#}
#
#function generate_configs() {
#
#  rm -fr al.conf
#  cat <<EOF >al.conf
## "DEVICE", where arch linux will be installed,
## Available options:
##    - one of: ("${DEVICES[@]}") - will erase all from device
##          *** If "ALONGSIDE" option is "true" then arch linux will try to install in the available space on the device
#DEVICE="$DEVICE"
## alongside will create another boot partition (TODO: don't do that in future)
#ALONGSIDE="$ALONGSIDE"
#BOOT_MOUNT="$BOOT_MOUNT"
## in MB, this create a swapfile
#SWAP_SIZE="$SWAP_SIZE"
## for better network speed
#REFLECTOR_COUNTRIES=$(print_array "${REFLECTOR_COUNTRIES[@]}")
## change it!
#ROOT_PASSWORD="$ROOT_PASSWORD"
## time zone "ls /usr/share/zoneinfo" to see other options
#TIMEZONE="$TIMEZONE"
# # a list with locale, first in list will be used to set system language
#LOCALES=$(print_array "${LOCALES[@]}")
# # keyboard layout
#KEYMAP="$KEYMAP"
## name of the new system
#HOSTNAME="$HOSTNAME"
## (username password)
#ADMIN_USER=$(print_array "${ADMIN_USER[@]}")
#
#OFFICIAL_PACKAGES=$(print_array "${OFFICIAL_PACKAGES[@]}")
#AUR_PACKAGES=$(print_array "${AUR_PACKAGES[@]}")
#
## "LOG_FILE", log location, absolute path only
#LOG_FILE="$LOG_FILE"
#
#EOF
#}
#
#function install_arch_linux() {
#
#  function last_partition_name() {
#    local last_partition
#    local last_partition_tokens
#
#    last_partition=$(fdisk "$DEVICE" -l | tail -1)
#    IFS=" " read -r -a last_partition_tokens <<<"$last_partition"
#
#    echo "${last_partition_tokens[0]}"
#  }
#
#  function last_partition_end_mb() {
#    local last_partition
#    local last_partition_tokens
#
#    last_partition=$(parted "$DEVICE" unit MB print | tail -2)
#    IFS=" " read -r -a last_partition_tokens <<<"$last_partition"
#    if [[ "${last_partition_tokens[2]}" == *MB ]]; then
#      echo "${last_partition_tokens[2]}"
#    else
#      echo "0%"
#    fi
#  }
#
#  function add_mb() {
#    local a
#    local b
#    local c
#    a=$(echo "$1" | awk -v FS='(|MB)' '{print $1}')
#    b=$(echo "$2" | awk -v FS='(|MB)' '{print $1}')
#    c=$(echo "$a + $b" | bs)
#    echo "${c}MB"
#  }
#
#  function init() {
#    loadkeys us
#    timedatectl set-ntp true
#
#    # only on ping -c 1, packer gets stuck if -c 5
#    local ping
#    ping=$(ping -c 1 -i 2 -W 5 -w 30 "mirrors.kernel.org")
#    if [[ "$ping" == 0 ]]; then
#      echo "Network ping check failed. Cannot continue."
#      exit 1
#    fi
#  }
#
#  function partition() {
#    local LAST_MB
#    local NEXT_SIZE
#    if [[ "$ALONGSIDE" == false ]]; then
#      sgdisk --zap-all "$DEVICE"
#      wipefs -a "$DEVICE"
#
#      if [ -d /sys/firmware/efi ]; then
#        parted "$DEVICE" mklabel gpt
#      else
#        parted "$DEVICE" mklabel msdos
#      fi
#    fi
#
#    LAST_MB=$(last_partition_end_mb)
#    if [[ "$LAST_MB" == 0% ]]; then
#      NEXT_SIZE="512MB"
#    else
#      NEXT_SIZE=$(add_mb "$LAST_MB" 512MB)
#    fi
#    parted "$DEVICE" mkpart primary "$LAST_MB" "$NEXT_SIZE"
#    parted "$DEVICE" set 1 boot on
#    if [ -d /sys/firmware/efi ]; then
#      parted "$DEVICE" set 1 esp on
#    fi
#    PARTITION_BOOT=$(last_partition_name "$DEVICE")
#
#    LAST_MB=$(last_partition_end_mb)
#    parted "$DEVICE" mkpart primary "$LAST_MB" 100%
#    PARTITION_ROOT=$(last_partition_name "$DEVICE")
#
#    if [ -d /sys/firmware/efi ]; then
#      mkfs.fat -n ESP -F32 "$PARTITION_BOOT"
#    else
#      mkfs.ext4 -L boot "$PARTITION_BOOT"
#    fi
#    mkfs.ext4 -L root "$PARTITION_ROOT"
#
#    mount -o "defaults,noatime" "$PARTITION_ROOT" /mnt
#    mkdir -p /mnt"$BOOT_MOUNT"
#    mount -o "defaults,noatime" "$PARTITION_BOOT" /mnt"$BOOT_MOUNT"
#
#    dd if=/dev/zero of=/mnt"$SWAPFILE" bs=1M count="$SWAP_SIZE" status=progress
#    chmod 600 /mnt"$SWAPFILE"
#    mkswap /mnt"$SWAPFILE"
#  }
#
#  function install_arch() {
#    if [ "${#REFLECTOR_COUNTRIES[@]}" != 0 ]; then
#      local COUNTRIES=()
#      local COUNTRY
#      for COUNTRY in "${REFLECTOR_COUNTRIES[@]}"; do
#        COUNTRIES+=(--country "${COUNTRY}")
#      done
#      pacman -Sy --noconfirm reflector
#      reflector "${COUNTRIES[@]}" --latest 25 --age 24 --protocol https --completion-percent 100 --sort rate --save /etc/pacman.d/mirrorlist
#    fi
#
#    local VIRTUALBOX=""
#    if lspci | grep -q -i virtualbox; then
#      VIRTUALBOX=(virtualbox-guest-utils virtualbox-guest-dkms)
#    fi
#    pacstrap /mnt base base-devel linux linux-headers linux-firmware "${VIRTUALBOX[@]}"
#  }
#
#  function configure_arch() {
#    ln -s -f "$TIMEZONE" /etc/localtime
#    hwclock --systohc
#    local locale
#    for locale in "${LOCALES[@]}"; do
#      sed -i "s/#$locale/$locale/" /etc/locale.gen
#    done
#    locale-gen
#    local LANG
#    LANG=$(echo "${LOCALES[0]}" | awk -v FS=' ' '{print $1}')
#    echo -e "LANG=$LANG" >>/etc/locale.conf
#    echo -e "KEYMAP=$KEYMAP" >/etc/vconsole.conf
#    echo "$HOSTNAME" >/etc/hostname
#
#    printf "%s\n%s\n" "$ROOT_PASSWORD" "$ROOT_PASSWORD" | passwd
#
#    {
#      echo "[multilib]"
#      echo "Include = /etc/pacman.d/mirrorlist"
#    } >>/etc/pacman.conf
#    sed -i 's/#Color/Color/' /etc/pacman.conf
#    sed -i 's/#TotalDownload/TotalDownload/' /etc/pacman.conf
#    pacman -Sy
#
#    sed -i "s/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/" /etc/sudoers
#
#    {
#      genfstab -U /mnt
#      echo "# swap"
#      echo "$SWAPFILE none swap defaults 0 0"
#      echo ""
#    } >>/etc/fstab
#
#    if ! lsblk "$DEVICE" --discard | grep -q 0B; then
#      systemctl enable fstrim.timer
#    fi
#
#    pacman -Sy --noconfirm networkmanager
#    systemctl enable NetworkManager.service
#
#    pacman -Sy --noconfirm efibootmgr grub
#    sed -i 's/GRUB_DEFAULT=0/GRUB_DEFAULT=saved/' /etc/default/grub
#    sed -i "s/#GRUB_SAVEDEFAULT=\"true\"/GRUB_SAVEDEFAULT=\"true\"/" /etc/default/grub
#    grub-install --target=x86_64-efi --bootloader-id=grub --efi-directory="$BOOT_MOUNT" --recheck
#    grub-mkconfig -o "/boot/grub/grub.cfg"
#    if lspci | grep -q -i virtualbox; then
#      echo -n "\EFI\grub\grubx64.efi" >"$BOOT_MOUNT/startup.nsh"
#    fi
#
#    if lspci | grep -q -i virtualbox; then
#      pacman -Sy --noconfirm openssh
#      systemctl enable sshd
#
#      local SSH_USERNAME=vagrant
#      local SSH_PASSWORD=vagrant
#      local PASSWORD
#      PASSWORD=$(openssl passwd -crypt "${SSH_PASSWORD}")
#
#      # Vagrant-specific configuration
#      useradd --password "${PASSWORD}" --comment 'Vagrant User' --create-home --user-group "${SSH_USERNAME}"
#      echo 'Defaults env_keep += "SSH_AUTH_SOCK"' > /etc/sudoers.d/10_"${SSH_USERNAME}"
#      echo "${SSH_USERNAME} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/10_"${SSH_USERNAME}"
#      chmod 0440 /etc/sudoers.d/10_"${SSH_USERNAME}"
#    fi
#  }
#
#  log "${FUNCNAME[0]}"
#
#  init
#  partition
#  install_arch
#  arch_chroot_fn /mnt configure_arch
#
#}
#
#function install_official_packages() {
#  log "${FUNCNAME[0]}"
#
#  pacman -Sy --noconfirm "${OFFICIAL_PACKAGES[@]}"
#}
#
#function install_aur_packages() {
#  log "${FUNCNAME[0]}"
#
#  yay -Sy --noconfirm "${AUR_PACKAGES[@]}"
#}
#
#function install_yay() {
#  log "${FUNCNAME[0]}"
#
#  function install() {
#    cd ~
#    git clone https://aur.archlinux.org/yay.git
#    cd yay
#    makepkg -si --noconfirm
#    cd ..
#    rm -rf yay
#  }
#
#  pacman -Sy --noconfirm git
#
#  sed -i "s/%wheel ALL=(ALL) ALL/%wheel ALL=(ALL) NOPASSWD: ALL/" /etc/sudoers
#  useradd -m -G wheel,storage,optical -s /bin/bash al
#  su al -c "
#    $(type install | tail +2)
#    install
#  "
#  userdel -fr al
#  sed -i "s/%wheel ALL=(ALL) NOPASSWD: ALL/%wheel ALL=(ALL) ALL/" /etc/sudoers
##  useradd -m -G wheel,storage,optical -s /bin/bash al
##  user_fn al install
##  userdel -fr al
#}
#
#function add_admin_user() {
#  log "${FUNCNAME[0]}"
#
#  useradd -m -G wheel,storage,optical -s /bin/bash "${ADMIN_USER[0]}"
#  printf "%s\n%s\n" "${ADMIN_USER[1]}" "${ADMIN_USER[1]}" | passwd "${ADMIN_USER[0]}"
#}
#
## does not handle function dependency
#function process_fn() {
#  local VERBOSE
#  if args_contains_el -v; then
#    VERBOSE='set -x'
#  fi
#  local RUN
#  RUN="
#    $VERBOSE
#    $(collect_variables)
#    $(type args_contains_el | tail +2)
#    $(type collect_variables | tail +2)
#    $(type user_fn | tail +2)
#    $(type process_fn | tail +2)
#    $(type log | tail +2)
#    $(type "$1" | tail +2)
#    $1
#  "
#
#  echo "$RUN"
#}
#
#function arch_chroot_fn() {
#  local RUN
#  RUN=$(process_fn "$2")
#  arch-chroot "$1" bash -c "$RUN"
#}
#
#function user_fn() {
#  local RUN
#  RUN=$(process_fn "$2")
#  sed -i "s/%wheel ALL=(ALL) ALL/%wheel ALL=(ALL) NOPASSWD: ALL/" /etc/sudoers
#  su "$1" -c "$RUN"
#  sed -i "s/%wheel ALL=(ALL) NOPASSWD: ALL/%wheel ALL=(ALL) ALL/" /etc/sudoers
#}
#
##function arch_chroot_user_fn() {
##  local RUN
##  RUN=$(process_fn "$3")
##  mkdir -p "$1"/home/work
##  echo "${RUN}" > "$1"/home/work/run.sh
###  chmod +x "$1"/home/work/run.sh
##  chmod ugo+xwr "$1"/home/work
##  arch-chroot "$1" bash -c "
##    sed -i \"s/%wheel ALL=(ALL) ALL/%wheel ALL=(ALL) NOPASSWD: ALL/\" /etc/sudoers
##    su $2 -c /home/work/run.sh
##    sed -i \"s/%wheel ALL=(ALL) NOPASSWD: ALL/%wheel ALL=(ALL) ALL/\" /etc/sudoers
##  "
##  rm -fr "$1"/home/work
##}
#
#function start_collect_variables() {
#  INITIAL_VARIABLES=$(compgen -v | tr "\n" " ")
#  IFS=' ' read -r -a INITIAL_VARIABLES <<<"$INITIAL_VARIABLES"
#}
#
#function collect_variables() {
#  FINALE_VARIABLES=$(compgen -v | tr "\n" " ")
#  IFS=' ' read -r -a FINALE_VARIABLES <<<"$FINALE_VARIABLES"
#
#  local VARIABLE
#  local var
#  for var in "${FINALE_VARIABLES[@]}"; do
#    if ! arr_contains_el "$var" "${INITIAL_VARIABLES[@]}" && [[ "$var" != INITIAL_VARIABLES ]]; then
#      VARIABLE="
#        $VARIABLE
#        $(declare -p | grep -e " $var=")
#      "
#    fi
#  done
#
#  echo "$VARIABLE"
#}
#
#function print_array() {
#  local res=()
#  local el
#  for el in "$@"; do
#    res+=("\"$el\"")
#  done
#
#  echo "(${res[*]})"
#}
#
#function arr_contains_el() {
#  local ARGS=("$@")
#  local arg
#  for ((arg = 1; arg < "${#ARGS[@]}"; arg++)); do
#    if [[ "${ARGS[$arg]}" == "$1" ]]; then
#      return 0 # emit no error
#    fi
#  done
#
#  return 1 # emit error
#}
#
#function device_list() {
#  local DEVICES
#  DEVICES=$(lsblk | grep disk | awk -v FS=' ' '{print "/dev/"$1}' | tr "\n" " ")
#  echo "$DEVICES"
#}
#
#function load_defaults() {
#
#  local DEVICES
#  DEVICES=$(device_list)
#  IFS=' ' read -r -a DEVICES <<<"$DEVICES"
#
#  LOG_FILE='/var/log/al.log'
#  DEVICE="${DEVICES[0]}"
#  ALONGSIDE=false
#  PARTITION_BOOT=""
#  PARTITION_ROOT=""
#  BOOT_MOUNT="/boot/efi"
#  SWAPFILE="/swapfile"
#  SWAP_SIZE="8192"
#  REFLECTOR_COUNTRIES=(Romania)
#  ROOT_PASSWORD="archlinux"
#  TIMEZONE="/usr/share/zoneinfo/Europe/Bucharest"
#  LOCALES=("en_US.UTF-8 UTF-8" "ro_RO.UTF-8 UTF-8")
#  KEYMAP="us"
#  HOSTNAME="archlinux"
#  ADMIN_USER=(admin admin)
#  OFFICIAL_PACKAGES=(nano zip unzip wget)
#  AUR_PACKAGES=(google-chrome)
#}
#
#function load_config_file() {
#
#  if [[ -f al.conf ]]; then
#    source al.conf
#  fi
#}
#
#function load_inline() {
#
#  function assign_arg() {
#    if args_contains_el "$1" && [[ "$ARG_VAL" != '' ]]; then
#      eval "$2=$ARG_VAL"
#    fi
#  }
#
#  assign_arg --log LOG_FILE
#  assign_arg archlinux DEVICE
#  assign_arg admin-user ADMIN_USER
#  assign_arg official-packages OFFICIAL_PACKAGES
#  assign_arg aur-packages AUR_PACKAGES
#}
#
## TODO: do more checks on variable !!!
#function check_variable_integrity() {
#
#  local DEVICES
#  DEVICES=$(device_list)
#  IFS=' ' read -r -a DEVICES <<<"$DEVICES"
#  if args_contains_el archlinux && ! arr_contains_el "$DEVICE" "${DEVICES[@]}"; then
#    echo -e "
#      Device \"$DEVICE\" not found! Choose one from $(print_array "${DEVICES[*]}")!
#    "
#    exit 1
#  fi
#
#  if args_contains_el aur-packages; then
#    if args_contains_el archlinux; then
#      if ! args_contains_el admin-user; then
#        echo -e "
#          You must provide an admin user!
#        "
#        exit 1
#      fi
#    else
#      if [[ $(id -u "$USER") == 0 ]]; then
#        echo -e "
#          You must be login with an not root user!
#        "
#        exit 1
#      fi
#    fi
#  fi
#}
#
#function manage_variable() {
#  load_defaults
#  load_config_file
#  load_inline
#}
#
#function run_in_order() {
#  run --log init_log
#  run --help show_help true
#  run -h show_help true
#  run --generate-config-template generate_configs true
#  run -v init_verbose
#
#  check_variable_integrity
#
#  run archlinux install_arch_linux
#  run admin-user "$(archlinux_prefix) add_admin_user"
#  run official-packages "$(archlinux_prefix) install_official_packages"
#  run aur-packages "$(archlinux_prefix) install_yay"
##  run aur-packages "arch_chroot_user_fn /mnt ${ADMIN_USER[0]} install_aur_packages"
#
#  run archlinux reboot
#}
#
#function main() {
#  local ARGS=("$@")
#
#  local ARG_VAL
#  function args_contains_el() {
#    local arg
#    for arg in "${ARGS[@]}"; do
#      if [[ "$arg" == "$1" ]] || [[ "$arg" == "$1"=* ]]; then
#        ARG_VAL=$(echo "$arg" | awk -v FS='(|=)' '{print $2}')
#        return 0 # emit no error
#      fi
#    done
#
#    return 1 # emit error
#  }
#
#  function log() {
#    if args_contains_el --log; then
#      echo "*********************$1*******************"
#    fi
#  }
#
#  function run() {
#    if args_contains_el "$1"; then
#      eval "$2"
#      if [[ "$3" == true ]]; then
#        exit 0
#      fi
#    fi
#  }
#
#  function archlinux_prefix() {
#    if args_contains_el archlinux; then
#      echo "arch_chroot_fn /mnt "
#    else
#      echo ""
#    fi
#  }
#
##  function process_user() {
##    if args_contains_el admin-user; then
##      echo "${ADMIN_USER[0]}"
##    else
##      echo "$USER"
##    fi
##  }
#
#  manage_variable
#  run_in_order
#}
#
#start_collect_variables
#main "$@"
#
#exit 0
