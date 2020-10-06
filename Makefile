build-box:
	packer build -force al.pkr.hcl

test-vagrant:
	vagrant box add output_box/al-virtualbox-*.box --force --name al
	vagrant destroy -f
	vagrant up
