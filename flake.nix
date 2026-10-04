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
    vmSettings = import ./settings.nix;
    system = vmSettings.system;

    pkgs = import nixpkgs {
      inherit system;
    };

    vmConfig = self.nixosConfigurations.coding-vm.config;
    vmDrv = vmConfig.system.build.vm;

    runVm = pkgs.writeShellApplication {
      name = "run-vm";

      runtimeInputs = [
        pkgs.coreutils
        pkgs.findutils
        pkgs.fuse3
        pkgs.gawk
        pkgs.gnugrep
        pkgs.gnused
        pkgs.kitty
        pkgs.nix
        pkgs.qemu_kvm
        pkgs.e2fsprogs
        pkgs.iproute2
        pkgs.tailscale
        pkgs.openssh
        pkgs.python3
        pkgs.sshfs
        pkgs.systemd
        pkgs.util-linux
      ];

      text = ''
        export CODING_VM_PROJECT_ROOT="''${CODING_VM_PROJECT_ROOT:-$PWD}"
        export VM_USER=${vmSettings.user}
        export VM_NETWORK_INTERFACE=${vmSettings.spoofSettings.network.interface}
        export VM_DNS4=${vmSettings.spoofSettings.network.dns4}
        export VM_DNS6=${vmSettings.spoofSettings.network.dns6}
        export VM_REQUIRE_TAILSCALE_EXIT=${
          if vmSettings.spoofSettings.enable
          then "1"
          else "0"
        }
        export VM_BUILD=${vmDrv}
        export VM_RUNNER_DIR=${vmDrv}/bin
        export VM_DISK_SIZE_MB=${toString vmConfig.virtualisation.diskSize}
        export VM_DISK_PREPARER=${./scripts/prepare-vm-disk.sh}
        exec bash ${./scripts/run-vm.sh}

      '';
    };
  in {
    nixosConfigurations.coding-vm = nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {inherit nixpkgs cachyos-kernel vmSettings;};
      modules = [./hosts/coding-vm.nix];
    };

    packages.${system} = {
      run-vm = runVm;
      default = runVm;
    };

    apps.${system} = {
      run-vm = {
        type = "app";
        program = "${runVm}/bin/run-vm";
      };
    };

    devShells.${system} = {
      tools = pkgs.mkShell {
        packages = with pkgs; [alejandra shfmt shellcheck python3 openssh curl iproute2 passt qemu_kvm e2fsprogs util-linux];
      };

      default = pkgs.mkShell {
        packages = [
          runVm
          pkgs.git
          pkgs.openssh
          pkgs.python3
          pkgs.sshfs
        ];

        shellHook = ''
          export CODING_VM_PROJECT_ROOT="$PWD"
          echo "Start the VM: run-vm"
        '';
      };
    };
  };
}
