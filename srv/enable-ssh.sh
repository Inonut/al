#!/usr/bin/env bash

SSH_USERNAME=$1
SSH_PASSWORD=$2
PASSWORD=$(/usr/bin/openssl passwd -crypt ${SSH_PASSWORD})

# Vagrant-specific configuration
/usr/bin/useradd --password ${PASSWORD} --comment 'Vagrant User' --create-home --user-group ${SSH_USERNAME}
echo 'Defaults env_keep += "SSH_AUTH_SOCK"' > /etc/sudoers.d/10_${SSH_USERNAME}
echo "${SSH_USERNAME} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/10_${SSH_USERNAME}
/usr/bin/chmod 0440 /etc/sudoers.d/10_${SSH_USERNAME}
/usr/bin/systemctl start sshd.service
