locals {
  ssh_username = "vagrant"
  ssh_password = "vagrant"
  output_box = "./output_box"
  arch_version = "{{isotime \"2006.01\"}}"
}

source "virtualbox-iso" "arch-linux" {
  guest_os_type = "ArchLinux_64"
  guest_additions_mode = "disable"
  headless = true
  http_directory = "."
  vboxmanage = [
    ["modifyvm", "{{.Name}}", "--memory", "4048"],
    ["modifyvm", "{{.Name}}", "--vram", "128"],
    ["modifyvm", "{{.Name}}", "--cpus", "4"],
    ["modifyvm", "{{.Name}}", "--firmware", "efi"]
  ]
  disk_size = 25384
  hard_drive_interface = "sata"
  iso_url = "https://mirror.rackspace.com/archlinux/iso/${local.arch_version}.01/archlinux-${local.arch_version}.01-x86_64.iso"
  iso_checksum = "file:https://mirrors.kernel.org/archlinux/iso/${local.arch_version}.01/sha1sums.txt"
  ssh_username = "${local.ssh_username}"
  ssh_password = "${local.ssh_password}"
  boot_wait = "40s"
  ssh_timeout = "40m"
  shutdown_command = "sudo systemctl poweroff"
  boot_command = [
    "/usr/bin/curl -O http://{{ .HTTPIP }}:{{ .HTTPPort }}/al.sh<enter>",
    "/usr/bin/curl -O http://{{ .HTTPIP }}:{{ .HTTPPort }}/al_lib.sh<enter>",
    "chmod +x ./al.sh<enter>",
    "./al.sh<enter><wait5>",
  ]
}

build {
  sources = ["sources.virtualbox-iso.arch-linux"]

  provisioner "shell" {
    inline = ["sudo cat /var/log/al.log"]
  }

  post-processor "vagrant" {
    output = "${local.output_box}/al-{{ .Provider }}-${local.arch_version}.box"
  }
}
