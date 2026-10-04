{modulesPath, ...}: {
  imports = [
    (modulesPath + "/virtualisation/qemu-vm.nix")
    ../modules/system/base.nix
    ../modules/system/users.nix
    ../modules/system/ssh.nix
    ../modules/environment/region.nix
    ../modules/environment/development.nix
    ../modules/environment/desktop.nix
    ../modules/vm/kernel.nix
    ../modules/vm/storage.nix
    ../modules/vm/graphics.nix
    ../modules/vm/host-tools.nix
    ../modules/vm/network.nix
  ];
}
