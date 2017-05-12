# This Vagrant file defines a Virtual Machine to quickly start with
# devPanel.
#
# This virtual machine contains devPanel pre-installed in the latest LTS
# version of Ubuntu 64 bits. Just after provisioning, the devPanel scripts
# and packages are updated. By default the network uses the virtual private
# interface with IP from DHCP, and the hostname is assigned based on IP address.
#
# Currently the only provider supported is Virtualbox.

Vagrant.configure("2") do |config|
  config.vm.define "test-1.devpanel.net"
  config.vm.box = "devpanel/ubuntu64"
  config.vm.box_url = "https://www.devpanel.com/vagrant/boxes.json"
end
