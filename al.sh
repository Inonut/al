#!/usr/bin/env bash

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

###################
####<< TOOLS >>####
###################

function init_log_no_param() {
  init_log "$LOG_FILE"
}

function init_verbose() {
  set -x
}

function show_help() {
  local DEVICES
  DEVICES=$(device_list)
  IFS=' ' read -r -a DEVICES <<<"$DEVICES"

  echo -e "
    This is a arch linux installer script. Also have some preconfigured packages.
    You can use it with a configuration file \"al.conf\" or inline commands.
    Command arguments override file arguments. If no value is provide then an error is shown.
  "
  echo -e "
    Options:
  "
  column -t -s '|' <<<"
            -v                                                                  | Verbose mode.
            --log                                                               | Log all output into a file /var/log/al.log
            --generate-config-template                                          | Generate an template with all possible options in './al.conf'
  "
  echo -e "
    Preconfigured packages:
  "
  column -t -s '|' <<<"
            * | archlinux[=\"$DEVICE\"]                                        | Install arch linux on device with defaults; This will wipe all of your data from device.
              |                                                                | For more options use configuration file \"--generate-config-template\"
              |                                                                | Available devices: (${DEVICES[*]})
            * | admin-user[='$(print_array "${ADMIN_USER[@]}")']               | Add admin user; format: '(user pass)'
            * | official-packages[='$(print_array "${OFFICIAL_PACKAGES[@]}")'] | Install official Arch Linux packages with pacman
            * | aur-packages[='$(print_array "${AUR_PACKAGES[@]}")']           | Install aur Arch Linux packages with yay
            * | all                                                            | Install: gnome, official-packages, aur-packages
            * | gnome                                                          | Install and configure Gnome
            * | systemd-hooks                                                  | Configure system with systemd profile; Add some aliases in .bashrc
  "
}

function generate_configs() {

  rm -fr al.conf
  cat <<EOF >al.conf
# "DEVICE", where arch linux will be installed,
# Available options:
#    - one of: ("${DEVICES[@]}") - will erase all from device
#          *** If "ALONGSIDE" option is "true" then arch linux will try to install in the available space on the device
DEVICE="$DEVICE"
# alongside will create another boot partition (TODO: don't do that in future)
ALONGSIDE="$ALONGSIDE"
BOOT_MOUNT="$BOOT_MOUNT"
# in MB, this create a swapfile
SWAP_SIZE="$SWAP_SIZE"
# for better network speed
REFLECTOR_COUNTRIES=$(print_array "${REFLECTOR_COUNTRIES[@]}")
# change it!
ROOT_PASSWORD="$ROOT_PASSWORD"
# time zone "ls /usr/share/zoneinfo" to see other options
TIMEZONE="$TIMEZONE"
 # a list with locale, first in list will be used to set system language
LOCALES=$(print_array "${LOCALES[@]}")
 # keyboard layout
KEYMAP="$KEYMAP"
# name of the new system
HOSTNAME="$HOSTNAME"
# (username password)
ADMIN_USER=$(print_array "${ADMIN_USER[@]}")

OFFICIAL_PACKAGES=$(print_array "${OFFICIAL_PACKAGES[@]}")
AUR_PACKAGES=$(print_array "${AUR_PACKAGES[@]}")

# "LOG_FILE", log location, absolute path only
LOG_FILE="$LOG_FILE"

EOF
}

function manage_variable() {

  function load_defaults() {
    local DEVICES
    DEVICES=$(device_list)
    IFS=' ' read -r -a DEVICES <<<"$DEVICES"

    LOG_FILE='/var/log/al.log'
    DEVICE="${DEVICES[0]}"
    ALONGSIDE=false
    BOOT_MOUNT="/boot/efi"
    SWAPFILE="/swapfile"
    SWAP_SIZE="4192"
    REFLECTOR_COUNTRIES=(Romania)
    ROOT_PASSWORD="archlinux"
    TIMEZONE="/usr/share/zoneinfo/Europe/Bucharest"
    LOCALES=("en_US.UTF-8 UTF-8" "ro_RO.UTF-8 UTF-8")
    KEYMAP="us"
    HOSTNAME="archlinux"
    ADMIN_USER=(admin admin)
    VAGRANT_USER=(vagrant vagrant)
    OFFICIAL_PACKAGES=(nano zip unzip wget)
    AUR_PACKAGES=(google-chrome)
  }

  function load_config_file() {

    if [[ -f al.conf ]]; then
      source al.conf
    fi
  }

  function load_inline() {

    function assign_arg() {
      if args_contains_el "$1" && [[ "$ARG_VAL" != '' ]]; then
        eval "$2=$ARG_VAL"
      fi
    }

    assign_arg --vm VAGRANT_USER
    assign_arg archlinux DEVICE
    assign_arg admin-user ADMIN_USER
    assign_arg official-packages OFFICIAL_PACKAGES
    assign_arg aur-packages AUR_PACKAGES
  }

  load_defaults
  load_config_file
  load_inline
}

function install_user_vagrant() {
  log "${FUNCNAME[0]}"

  pacman -Sy --noconfirm --needed openssh

  local SSH_USERNAME="${VAGRANT_USER[0]}"
  local SSH_PASSWORD="${VAGRANT_USER[1]}"
  local PASSWORD
  PASSWORD=$(openssl passwd -crypt "${SSH_PASSWORD}")

  # Vagrant-specific configuration
  useradd --password "${PASSWORD}" --comment 'Vagrant User' --create-home --user-group "${SSH_USERNAME}"
  echo "${SSH_USERNAME} ALL=(ALL) NOPASSWD: ALL" >>/etc/sudoers.d/10_"${SSH_USERNAME}"
  chmod +x /etc/sudoers.d/10_"${SSH_USERNAME}"

  systemctl enable sshd
  systemctl start sshd
}

# TODO: do more checks on variable !!!
function check_variable_integrity() {

  local DEVICES
  DEVICES=$(device_list)
  IFS=' ' read -r -a DEVICES <<<"$DEVICES"
  if args_contains_el archlinux && ! arr_contains_el "$DEVICE" "${DEVICES[@]}"; then
    echo -e "
      Device \"$DEVICE\" not found! Choose one from $(print_array "${DEVICES[*]}")!
    "
    exit 1
  fi

  if args_contains_el aur-packages; then
    if args_contains_el archlinux; then
      if ! args_contains_el admin-user; then
        echo -e "
          You must provide an admin user!
        "
        exit 1
      fi
    else
      if [[ $(id -u "$SUDO_USER") == 0 ]]; then
        echo -e "
          You must be login with an not root user!
        "
        exit 1
      fi
    fi
  fi
}

function install_arch_linux() {

  function last_partition_name() {
    local last_partition
    local last_partition_tokens

    last_partition=$(fdisk "$DEVICE" -l | tail -1)
    IFS=" " read -r -a last_partition_tokens <<<"$last_partition"

    echo "${last_partition_tokens[0]}"
  }

  function last_partition_end_mb() {
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

  function add_mb() {
    local a
    local b
    local c
    a=$(echo "$1" | awk -v FS='(|MB)' '{print $1}')
    b=$(echo "$2" | awk -v FS='(|MB)' '{print $1}')
    c=$(echo "$a + $b" | bs)
    echo "${c}MB"
  }

  function init() {
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

  function partition() {
    local LAST_MB
    local NEXT_SIZE
    if [[ "$ALONGSIDE" == false ]]; then
      sgdisk --zap-all "$DEVICE"
      wipefs -a "$DEVICE"

      if [ -d /sys/firmware/efi ]; then
        parted "$DEVICE" mklabel gpt
      else
        parted "$DEVICE" mklabel msdos
      fi
    fi

    LAST_MB=$(last_partition_end_mb)
    if [[ "$LAST_MB" == 0% ]]; then
      NEXT_SIZE="512MB"
    else
      NEXT_SIZE=$(add_mb "$LAST_MB" 512MB)
    fi
    parted "$DEVICE" mkpart primary "$LAST_MB" "$NEXT_SIZE"
    parted "$DEVICE" set 1 boot on
    if [ -d /sys/firmware/efi ]; then
      parted "$DEVICE" set 1 esp on
    fi
    PARTITION_BOOT=$(last_partition_name "$DEVICE")

    LAST_MB=$(last_partition_end_mb)
    parted "$DEVICE" mkpart primary "$LAST_MB" 100%
    PARTITION_ROOT=$(last_partition_name "$DEVICE")

    if [ -d /sys/firmware/efi ]; then
      mkfs.fat -n ESP -F32 "$PARTITION_BOOT"
    else
      mkfs.ext4 -L boot "$PARTITION_BOOT"
    fi
    mkfs.ext4 -L root "$PARTITION_ROOT"

    mount -o "defaults,noatime" "$PARTITION_ROOT" /mnt
    mkdir -p /mnt"$BOOT_MOUNT"
    mount -o "defaults,noatime" "$PARTITION_BOOT" /mnt"$BOOT_MOUNT"

    dd if=/dev/zero of=/mnt"$SWAPFILE" bs=1M count="$SWAP_SIZE" status=progress
    chmod 600 /mnt"$SWAPFILE"
    mkswap /mnt"$SWAPFILE"
  }

  function install_arch() {
    if [ "${#REFLECTOR_COUNTRIES[@]}" != 0 ]; then
      local COUNTRIES=()
      local COUNTRY
      for COUNTRY in "${REFLECTOR_COUNTRIES[@]}"; do
        COUNTRIES+=(--country "${COUNTRY}")
      done
      pacman -Sy --noconfirm --needed reflector
      reflector "${COUNTRIES[@]}" --latest 25 --age 24 --protocol https --completion-percent 100 --sort rate --save /etc/pacman.d/mirrorlist
    fi

    local VIRTUALBOX=""
    if lspci | grep -q -i virtualbox; then
      VIRTUALBOX=(virtualbox-guest-utils virtualbox-guest-dkms)
    fi
    pacstrap /mnt base base-devel linux linux-headers linux-firmware "${VIRTUALBOX[@]}"
  }

  function configure_arch() {
    ln -s -f "$TIMEZONE" /etc/localtime
    hwclock --systohc
    local locale
    for locale in "${LOCALES[@]}"; do
      sed -i "s/#$locale/$locale/" /etc/locale.gen
    done
    locale-gen
    local LANG
    LANG=$(echo "${LOCALES[0]}" | awk -v FS=' ' '{print $1}')
    echo -e "LANG=$LANG" >>/etc/locale.conf
    echo -e "KEYMAP=$KEYMAP" >/etc/vconsole.conf
    echo "$HOSTNAME" >/etc/hostname

    printf "%s\n%s\n" "$ROOT_PASSWORD" "$ROOT_PASSWORD" | passwd

    {
      echo "[multilib]"
      echo "Include = /etc/pacman.d/mirrorlist"
    } >>/etc/pacman.conf
    sed -i 's/#Color/Color/' /etc/pacman.conf
    sed -i 's/#TotalDownload/TotalDownload/' /etc/pacman.conf
    pacman -Sy

    sed -i "s/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/" /etc/sudoers

    {
      genfstab -U /mnt
      echo "# swap"
      echo "$SWAPFILE none swap defaults 0 0"
      echo ""
    } >>/etc/fstab

    if ! lsblk "$DEVICE" --discard | grep -q 0B; then
      systemctl enable fstrim.timer
    fi

    pacman -Sy --noconfirm --needed networkmanager
    systemctl enable NetworkManager.service

    pacman -Sy --noconfirm --needed efibootmgr grub
    sed -i 's/GRUB_DEFAULT=0/GRUB_DEFAULT=saved/' /etc/default/grub
    sed -i "s/#GRUB_SAVEDEFAULT=\"true\"/GRUB_SAVEDEFAULT=\"true\"/" /etc/default/grub
    grub-install --target=x86_64-efi --bootloader-id=grub --efi-directory="$BOOT_MOUNT" --recheck
    grub-mkconfig -o "/boot/grub/grub.cfg"
    if lspci | grep -q -i virtualbox; then
      echo -n "\EFI\grub\grubx64.efi" >"$BOOT_MOUNT/startup.nsh"
    fi
  }

  log "${FUNCNAME[0]}"

  init
  partition
  install_arch
  run_arch_chroot configure_arch
}

function add_admin_user() {
  log "${FUNCNAME[0]}"

  useradd -m -G wheel,storage,optical -s /bin/bash "${ADMIN_USER[0]}"
  printf "%s\n%s\n" "${ADMIN_USER[1]}" "${ADMIN_USER[1]}" | passwd "${ADMIN_USER[0]}"
}

function install_official_packages() {
  log "${FUNCNAME[0]}"

  pacman -Sy --noconfirm --needed "${OFFICIAL_PACKAGES[@]}"
}

function install_aur_packages() {
  log "${FUNCNAME[0]}"

  su "$SUDO_USER" -c "
    yay -Sy --noconfirm --needed ${AUR_PACKAGES[*]}
  "
}

function install_yay() {
  log "${FUNCNAME[0]}"

  if ! pacman -Q | grep -q yay; then
    pacman -Sy --noconfirm --needed git
    su "$SUDO_USER" -c "
      cd ~
      git clone https://aur.archlinux.org/yay.git
      cd yay
      makepkg -si --noconfirm --needed
      cd ..
      rm -rf yay
    "
  fi
}

function configure_systemd_hooks() {
  log "${FUNCNAME[0]}"

  cat <<EOT >>/etc/bash.bashrc
alias ll='ls -alF'
PS1='\[\033[01;32m\][\u@\h\[\033[01;37m\] \W\[\033[01;32m\]]\$\[\033[00m\] '
EOT

  local USERS_HOME
  local USER_HOME
  USERS_HOME=$(cat /etc/passwd | grep bash | awk -v FS=':' '{print $6}' | tr '\n' ' ')
  IFS=' ' read -r -a USERS_HOME <<<"$USERS_HOME"
  for USER_HOME in "${USERS_HOME[@]}"; do
    if test -f "$USER_HOME/.bashrc"; then
      sed -i 's/PS1=/#PS1=/g' "$USER_HOME/.bashrc"
    fi
  done
}

function install_gnome() {
  log "${FUNCNAME[0]}"

  su "$SUDO_USER" -c "
    yay -S --noconfirm --needed gnome gnome-extra matcha-gtk-theme bash-completion xcursor-breeze papirus-maia-icon-theme-git noto-fonts ttf-hack gnome-shell-extensions gnome-shell-extension-topicons-plus
    yay -Rs --noconfirm --needed gnome-terminal
    yay -S --noconfirm --needed gnome-terminal-transparency
  "
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

function run_in_order() {

  function run() {
    local ELEMENTS
    local EL
    IFS=' ' read -r -a ELEMENTS <<<"$1"
    for EL in "${ELEMENTS[@]}"; do
      if args_contains_el "$EL"; then
        eval "$2"
        if [[ "$3" == true ]]; then
          exit 0
        fi
        break
      fi
    done
  }

  function archlinux_prefix() {
    if args_contains_el archlinux; then
      echo "run_arch_chroot "
    else
      echo ""
    fi
  }

  function archlinux_prefix_user() {
    if args_contains_el archlinux; then
      echo "run_arch_chroot_user ${ADMIN_USER[0]} "
    else
      echo "run_user $SUDO_USER "
    fi
  }

  run --log init_log_no_param
  run --help show_help true
  run -h show_help true
  run --generate-config-template generate_configs true
  run -v init_verbose

  check_variable_integrity

  run archlinux install_arch_linux
  run admin-user "$(archlinux_prefix) add_admin_user"
  run "all official-packages" "$(archlinux_prefix) install_official_packages"
  run "all aur-packages gnome" "$(archlinux_prefix_user) install_yay"
  run "all aur-packages" "$(archlinux_prefix_user) install_aur_packages"
  run "all systemd-hooks" "$(archlinux_prefix) configure_systemd_hooks"
  run "all gnome" "$(archlinux_prefix_user) install_gnome"

  run --vm "$(archlinux_prefix) install_user_vagrant"
  if args_contains_el --log && args_contains_el archlinux; then
    cp "$LOG_FILE" "/mnt$LOG_FILE"
  fi

  run archlinux 'cp al.sh /mnt/al.sh'
  run archlinux reboot
}

function main() {
  local ARGS=("$@")

  local ARG_VAL
  function args_contains_el() {
    local arg
    for arg in "${ARGS[@]}"; do
      if [[ "$arg" == "$1" ]] || [[ "$arg" == "$1"=* ]]; then
        ARG_VAL=$(echo "$arg" | awk -v FS='(|=)' '{print $2}')
        return 0 # emit no error
      fi
    done

    return 1 # emit error
  }

  function log() {
    if args_contains_el --log; then
      echo "*********************$1*******************"
    fi
  }

  function run_arch_chroot() {
    local RUN
    RUN=$(build_inline_script "$1")
    echo "$RUN" >/mnt/run_arch_chroot.sh
    chmod +x /mnt/run_arch_chroot.sh
    arch-chroot /mnt bash /run_arch_chroot.sh
    rm -fr /mnt/run_arch_chroot.sh
  }

  function run_arch_chroot_user() {
    local RUN
    RUN=$(build_inline_script "$2")
    echo "$RUN" >/mnt/run_arch_chroot_user.sh
    chmod +x /mnt/run_arch_chroot_user.sh
    echo "$1 ALL=(ALL) NOPASSWD: ALL" >/mnt/etc/sudoers.d/10_"$1"
    chmod +x /mnt/etc/sudoers.d/10_"$1"
    arch-chroot /mnt su "$1" -c "sudo /run_arch_chroot_user.sh"
    rm -fr /mnt/etc/sudoers.d/10_"$1"
    rm -fr /mnt/run_arch_chroot_user.sh
  }

  function run_user() {
    local RUN
    RUN=$(build_inline_script "$2")
    echo "$RUN" >/run_user.sh
    chmod +x /run_user.sh
    echo "$1 ALL=(ALL) NOPASSWD: ALL" >/etc/sudoers.d/10_"$1"
    chmod +x /etc/sudoers.d/10_"$1"
    su "$1" -c "sudo /run_user.sh"
    rm -fr /etc/sudoers.d/10_"$1"
    rm -fr /run_user.sh
  }

  function build_inline_script() {
    local FN
    IFS=' ' read -r -a FN <<<"$1"
    local VERBOSE
    if args_contains_el -v; then
      VERBOSE='set -x'
    fi
    echo "
      $VERBOSE
      $(collect_variables)
      $(type args_contains_el | tail +2)
      $(type log | tail +2)
      $(type "${FN[0]}" | tail +2)
      $1
    "
  }

  manage_variable
  run_in_order
}

checkpoint_variables
main "$@"

exit 0
