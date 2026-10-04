{
  description = "Modular NixOS development VM with optional region and network presets";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.cachyos-kernel.url = "github:xddxdd/nix-cachyos-kernel/release";

  nixConfig = {
    extra-substituters = ["https://attic.xuyh0120.win/lantian"];
    extra-trusted-public-keys = ["lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="];
  };

  outputs = {
    self,
    nixpkgs,
    cachyos-kernel,
  }: let
    defaultSettings = import ./settings.nix;
    system = defaultSettings.system;
    pkgs = import nixpkgs {inherit system;};
    mkVM = settings: import ./lib/mk-vm.nix {inherit nixpkgs cachyos-kernel settings;};
    defaultVM = mkVM defaultSettings;
    managedVm = pkgs.writeShellApplication {
      name = "run-vm";
      runtimeInputs = [pkgs.python3 pkgs.git pkgs.nix];
      text = ''
        exec python3 ${./scripts/manage-vm.py} --project "''${CODING_VM_PROJECT_ROOT:-$PWD}" start "$@"
      '';
    };
  in {
    lib = {
      inherit mkVM;
      defaultSettings = defaultVM.effectiveSettings;
    };
    nixosConfigurations.coding-vm = defaultVM.nixosConfiguration;
    packages.${system} = {
      run-vm = managedVm;
      default = managedVm;
    };
    apps.${system} = {
      run-vm = {
        type = "app";
        program = "${managedVm}/bin/run-vm";
      };
      default = self.apps.${system}.run-vm;
    };
    templates.default = {
      path = ./templates/instance;
      description = "A coding VM instance with its own settings and lock file";
    };
    devShells.${system} = {
      tools = pkgs.mkShell {
        packages = with pkgs; [alejandra shfmt shellcheck python3 openssh curl iproute2 passt qemu_kvm e2fsprogs util-linux];
      };

      default = pkgs.mkShell {
        packages = [managedVm pkgs.git pkgs.openssh pkgs.python3 pkgs.sshfs];
        shellHook = ''
          export CODING_VM_PROJECT_ROOT="$PWD"
          echo "Start the VM: run-vm"
        '';
      };
    };
  };
}
