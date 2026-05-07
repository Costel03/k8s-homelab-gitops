VAGRANTFILE_API_VERSION = "2"

# Node definitions – easy to add/remove nodes
NODES = [
  { name: "k8s-master",  ip: "192.168.56.10", memory: 2048, cpus: 2},
  { name: "k8s-worker1", ip: "192.168.56.11", memory: 6144, cpus: 4 },
  { name: "k8s-worker2", ip: "192.168.56.12", memory: 6144, cpus: 4 },
]

Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|
  config.vm.box = "k8s-base"
  config.hostmanager.enabled = true
  config.hostmanager.manage_host = false

  NODES.each do |node_cfg|
    config.vm.define node_cfg[:name] do |node|
      node.vm.hostname = node_cfg[:name]
      node.vm.network "private_network", ip: node_cfg[:ip]
      node.vm.synced_folder ".", "/vagrant", disabled: true

      node.vm.provider :virtualbox do |v|
        v.name         = node_cfg[:name]
        v.memory       = node_cfg[:memory]
        v.cpus         = node_cfg[:cpus]
        v.linked_clone = true
        v.customize ["modifyvm", :id, "--paravirtprovider", "hyperv"]
        v.customize ["modifyvm", :id, "--nested-hw-virt", "on"]
      end
    end
  end
end
