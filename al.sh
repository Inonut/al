#!/usr/bin/env bash
set +e

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

# Git
GIT_USERNAME="admin"
GIT_EMAIL="admin@archlinux.com"

# Other variables generated by script will be store here
'

USAGE='

Script for installing Arch Linux and configure applications

options:
    --help                Show this help text
    --generate-defaults   Generate file al.conf
    --install-arch-uefi   Install Arch Linux in uefi mode, this erase all of your data
    --app-packages        Install all available packages
    --dev-packages        Install all dev specific available packages
    --yay                 Install yay, tool for installing packages from AUR
    --ssh                 Configure ssh
    --gnome               Install gnome as user interface
    --dynamic-wallpaper   Install variety to change wallpaper
    --chrome              Install Google Chrome
    --virtualbox          Install Virtualbox
    --git                 Install Git
    --vagrant             Install Vagrant
    --packer              Install Packer
    --maven               Install Maven
    --gradle              Install Gradle

'

function step() {
  echo "*********************$1**********************"
}

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
  step "${FUNCNAME[0]}"
  echo "$DEFAULT_OPTIONS" > al.conf
  echo "File al.conf was created!"
}

function init_log() {
  step "${FUNCNAME[0]}"
  local LOG_FILE
  read_variables LOG_FILE
  rm -f "$LOG_FILE"
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
  step "${FUNCNAME[0]}"
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

  local VIRTUALBOX=""
  if lspci | grep -q -i virtualbox; then
    VIRTUALBOX=(virtualbox-guest-utils virtualbox-guest-dkms intel-ucode)
  fi
  local UTIL_TOOLS=(wget nano zip unzip bash-completion)
  pacstrap /mnt base base-devel linux linux-headers networkmanager efibootmgr grub "${UTIL_TOOLS[@]}" "${VIRTUALBOX[@]}"

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
  step "${FUNCNAME[0]}"
  sudo pacman -S --noconfirm git
  git clone https://aur.archlinux.org/yay.git
  cd yay
  makepkg -si --noconfirm
  cd ..
  rm -rf yay
}

function install_ssh() {
  step "${FUNCNAME[0]}"
  sudo pacman -S --noconfirm openssh
  sudo systemctl enable sshd.service
  sudo systemctl start sshd.service
}

function install_gnome() {
  step "${FUNCNAME[0]}"
  if ! pacman -Q | grep yay; then
    install_yay
  fi

  yay -S --noconfirm gnome gnome-extra matcha-gtk-theme bash-completion xcursor-breeze papirus-maia-icon-theme-git noto-fonts ttf-hack gnome-shell-extensions gnome-shell-extension-topicons-plus
  yay -Rs --noconfirm gnome-terminal
  yay -S --noconfirm gnome-terminal-transparency
  sudo systemctl enable gdm.service
  sudo systemctl start gdm.service

  cat <<'EOT' >> gnome-dconf
#!/bin/bash

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
gsettings set org.gnome.shell.extensions.user-theme name 'Matcha-dark-sea'
gsettings set org.gnome.shell.weather automatic-location true
gsettings set org.gnome.system.location enabled true
gsettings set org.gnome.desktop.wm.keybindings show-desktop "['<Super>d']"
gsettings set org.gnome.desktop.wm.keybindings switch-applications "@as []"
gsettings set org.gnome.desktop.wm.keybindings switch-applications-backward "@as []"
gsettings set org.gnome.desktop.wm.keybindings switch-windows "['<Alt>Tab']"
gsettings set org.gnome.desktop.wm.keybindings switch-windows-backward "['<Shift><Alt>Tab']"
gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/']"
gsettings set org.gnome.settings-daemon.plugins.media-keys home "['<Super>e']"
gsettings set org.gnome.settings-daemon.plugins.media-keys www "['<Super>g']"
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ binding '<Primary><Alt>t'
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ command 'gnome-terminal'
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ name 'terminal'

git clone https://github.com/arcticicestudio/nord-gnome-terminal.git
cd nord-gnome-terminal/src
./nord.sh
rm -fr nord-gnome-terminal

query=$(dconf dump /org/gnome/terminal/legacy/profiles:/ | awk '/\[:/||/visible-name=/')
lines=( $query )
for i in "${!lines[@]}"; do
  if [[ "${lines[$i]}" == "visible-name='Nord'" ]]; then
    var=$(echo ${lines[$i - 1]} | tr -d ] | tr -d [ | tr -d :)
 fi
done

dconf write /org/gnome/terminal/legacy/profiles:/:$var/scrollbar-policy "'never'"
dconf write /org/gnome/terminal/legacy/profiles:/:$var/use-transparent-background "true"
dconf write /org/gnome/terminal/legacy/profiles:/:$var/background-transparency-percent "9"
dconf write /org/gnome/terminal/legacy/profiles:/:$var/default-size-columns "100"
dconf write /org/gnome/terminal/legacy/profiles:/:$var/default-size-rows "27"
dconf write /org/gnome/terminal/legacy/profiles:/default "'$var'"

rm ~/.config/autostart/gnome-dconf.desktop
rm $0
EOT

  mkdir -p ~/.config/autostart/
  cat <<EOT >> ~/.config/autostart/gnome-dconf.desktop
[Desktop Entry]
Comment[en_US]=
Comment=
Exec=./gnome-dconf
GenericName[en_US]=
GenericName=
Icon=system-run
MimeType=
Name[en_US]=gnome-dconf
Name=gnome-dconf
Path=
StartupNotify=true
Terminal=false
TerminalOptions=
Type=Application
X-DBUS-ServiceName=
X-DBUS-StartupType=
X-KDE-SubstituteUID=false
X-KDE-Username=
EOT

  chmod +x ./gnome-dconf
  if systemctl is-active --quiet dbus; then
    ./gnome-dconf
  fi

  cat <<EOT >> ~/.bashrc
alias ll='ls -alF'
PS1='\[\033[01;32m\][\u@\h\[\033[01;37m\] \W\[\033[01;32m\]]\$\[\033[00m\] '
EOT
}

function install_gnome_chrome_integration() {
  step "${FUNCNAME[0]}"
  sudo pacman -S --noconfirm chrome-gnome-shell
}

function install_dynamic_wallpaper() {
  step "${FUNCNAME[0]}"
  sudo pacman -S --noconfirm variety
#  mkdir -p ~/.config/variety
#  date +"%Y-%m-%d %H:%M:%S" > ~/.config/variety/.firstrun
#  variety -n &
  echo 'Use interface to configure it!'
}

function install_chrome() {
  step "${FUNCNAME[0]}"
  if ! pacman -Q | grep yay; then
    install_yay
  fi

  yay -S --noconfirm google-chrome
}

function install_docker() {
  step "${FUNCNAME[0]}"
  sudo pacman -S --noconfirm docker docker-compose

  sudo systemctl enable docker
  sudo systemctl start docker
  sudo usermod -aG docker "$USER"
  if systemctl is-active --quiet docker; then
    newgrp docker
  fi
}

function install_virtualbox() {
  step "${FUNCNAME[0]}"
  sudo pacman -S --noconfirm virtualbox virtualbox-host-modules-arch virtualbox-guest-iso

  sudo vboxreload
}

function install_git() {
  step "${FUNCNAME[0]}"
  local GIT_USERNAME
  local GIT_EMAIL
  read_variables GIT_USERNAME GIT_EMAIL
  sudo pacman -S --noconfirm git

  git config --global user.name "$GIT_USERNAME"
  git config --global user.email "$GIT_EMAIL"
}

function install_pack() {
  sudo pacman -S --noconfirm "$1"
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
    if [[ "${ARGS[*]}" =~ --yay ]] || [[ "${ARGS[*]}" =~ --app-packages ]]; then
      install_yay
    fi
    if [[ "${ARGS[*]}" =~ --gnome ]] || [[ "${ARGS[*]}" =~ --app-packages ]]; then
      install_gnome
      if [[ "${ARGS[*]}" =~ --chrome ]] || [[ "${ARGS[*]}" =~ --app-packages ]]; then
        install_gnome_chrome_integration
      fi
    fi
    if [[ "${ARGS[*]}" =~ --dynamic-wallpaper ]]; then
      install_dynamic_wallpaper
    fi
    if [[ "${ARGS[*]}" =~ --chrome ]] || [[ "${ARGS[*]}" =~ --app-packages ]]; then
      install_chrome
    fi
    if [[ "${ARGS[*]}" =~ --ssh ]] || [[ "${ARGS[*]}" =~ --dev-packages ]]; then
      install_ssh
    fi
    if [[ "${ARGS[*]}" =~ --docker ]] || [[ "${ARGS[*]}" =~ --dev-packages ]]; then
      install_docker
    fi
    if [[ "${ARGS[*]}" =~ --virtualbox ]] || [[ "${ARGS[*]}" =~ --dev-packages ]]; then
      install_virtualbox
    fi
    if [[ "${ARGS[*]}" =~ --git ]] || [[ "${ARGS[*]}" =~ --dev-packages ]]; then
      install_git
    fi
    if [[ "${ARGS[*]}" =~ --vagrant ]] || [[ "${ARGS[*]}" =~ --dev-packages ]]; then
      install_pack vagrant
    fi
    if [[ "${ARGS[*]}" =~ --packer ]] || [[ "${ARGS[*]}" =~ --dev-packages ]]; then
      install_pack packer
    fi
    if [[ "${ARGS[*]}" =~ --maven ]] || [[ "${ARGS[*]}" =~ --dev-packages ]]; then
      install_pack maven
    fi
    if [[ "${ARGS[*]}" =~ --gradle ]] || [[ "${ARGS[*]}" =~ --dev-packages ]]; then
      install_pack gradle
    fi
  fi
}

function main() {
  local ARGS=("$@")
  arguments_handler "${ARGS[@]}"
}

main "$@"

exit 1
