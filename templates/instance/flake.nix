{
  inputs.coding-vm.url = "github:MiRinChan/coding-vm.nix";
  outputs = {coding-vm, ...}: let
    vm = coding-vm.lib.mkVM (import ./settings.nix);
    system = vm.effectiveSettings.system;
  in {
    nixosConfigurations.coding-vm = vm.nixosConfiguration;
    packages.${system}.default = vm.runVm;
    apps.${system}.default = {
      type = "app";
      program = "${vm.runVm}/bin/run-vm";
    };
    lib = {
      inherit (vm) effectiveSettings behaviorManifest;
      packageVersions =
        map (pkg: {
          name = coding-vm.inputs.nixpkgs.lib.getName pkg;
          version = coding-vm.inputs.nixpkgs.lib.getVersion pkg;
        })
        (vm.nixosConfiguration.config.environment.systemPackages ++ [vm.nixosConfiguration.config.boot.kernelPackages.kernel]);
    };
  };
}
