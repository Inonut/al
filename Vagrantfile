Vagrant.configure("2") do |config|
  config.vm.box = "al"

  config.ssh.username = "vagrant"
  config.ssh.password = "vagrant"

  config.vm.provider "virtualbox" do |v|
    v.gui = true

    v.customize ["modifyvm", :id, "--clipboard", "bidirectional"]
  end
end
