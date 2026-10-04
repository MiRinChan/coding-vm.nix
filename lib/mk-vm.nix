{
  nixpkgs,
  cachyos-kernel,
  settings,
}: let
  lib = nixpkgs.lib;
  vmSettings = import ./normalize-settings.nix {inherit lib settings;};
  system = vmSettings.system;
  pkgs = import nixpkgs {inherit system;};
  nixosConfiguration = lib.nixosSystem {
    inherit system;
    specialArgs = {inherit nixpkgs cachyos-kernel vmSettings;};
    modules = [../hosts/coding-vm.nix];
  };
  vmConfig = nixosConfiguration.config;
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
      export VM_SSH_ALIAS=${lib.escapeShellArg vmSettings.launcher.sshAlias}
      export VM_SSH_PORT="''${VM_SSH_PORT:-${toString vmSettings.launcher.sshPort}}"
      export VM_SSH_TIMEOUT="''${VM_SSH_TIMEOUT:-${toString vmSettings.launcher.sshTimeoutSeconds}}"
      export VM_NOFILE_LIMIT=${toString vmSettings.launcher.nofileLimit}
      export VM_NETWORK_GUARD_INTERVAL=${toString vmSettings.launcher.networkGuardIntervalSeconds}
      export OPEN_VSCODE="''${OPEN_VSCODE:-${
        if vmSettings.launcher.openVSCode
        then "1"
        else "0"
      }}"
      export OPEN_KITTY_SSH="''${OPEN_KITTY_SSH:-${
        if vmSettings.launcher.openKitty
        then "1"
        else "0"
      }}"
      export MOUNT_SSHFS="''${MOUNT_SSHFS:-${
        if vmSettings.launcher.mountSSHFS
        then "1"
        else "0"
      }}"
      ${lib.optionalString (vmSettings.launcher.sshKey != null) ''
        if [ -z "''${VM_SSH_KEY:-}" ]; then
          export VM_SSH_KEY=${lib.escapeShellArg vmSettings.launcher.sshKey}
        fi
      ''}
      ${lib.optionalString (vmSettings.launcher.fsMountDir != null) ''
        if [ -z "''${VM_FS_MOUNT_DIR:-}" ]; then
          export VM_FS_MOUNT_DIR=${lib.escapeShellArg vmSettings.launcher.fsMountDir}
        fi
      ''}
      ${lib.optionalString (vmSettings.launcher.fsRemote != null) ''
        if [ -z "''${VM_FS_REMOTE:-}" ]; then
          export VM_FS_REMOTE=${lib.escapeShellArg vmSettings.launcher.fsRemote}
        fi
      ''}
      export VM_USER=${lib.escapeShellArg vmSettings.user}
      export VM_NETWORK_INTERFACE=${lib.escapeShellArg vmSettings.spoofSettings.network.interface}
      export VM_DNS4=${lib.escapeShellArg vmSettings.spoofSettings.network.dns4}
      export VM_DNS6=${lib.escapeShellArg vmSettings.spoofSettings.network.dns6}
      export VM_REQUIRE_TAILSCALE_EXIT=${
        if vmSettings.spoofSettings.enable
        then "1"
        else "0"
      }
      export VM_BUILD=${vmDrv}
      export VM_RUNNER_DIR=${vmDrv}/bin
      export VM_DISK_PREALLOCATE=${
        if vmSettings.resources.preallocateDisk
        then "1"
        else "0"
      }
      export VM_DISK_SIZE_MB=${toString vmConfig.virtualisation.diskSize}
      export VM_CONTROL_HELPER=${../scripts/vm-runtime.py}
      export VM_DISK_PREPARER=${../scripts/prepare-vm-disk.sh}
      exec bash ${../scripts/run-vm.sh}

    '';
  };
in {
  inherit nixosConfiguration runVm;
  effectiveSettings = vmSettings;
  behaviorManifest = {
    settings = vmSettings;
    launcherPolicyVersion = 2;
    effective = {
      inherit (vmConfig.virtualisation) cores memorySize diskSize writableStore writableStoreUseTmpfs;
      timeZone = vmConfig.time.timeZone;
      locale = vmConfig.i18n.defaultLocale;
      location = vmConfig.location;
      staticLocation = vmConfig.services.geoclue2.enableStatic;
      geoClue = vmConfig.services.geoclue2.enable;
      userGroups = vmConfig.users.users.${vmSettings.user}.extraGroups;
      mutableUsers = vmConfig.users.mutableUsers;
      wheelNeedsPassword = vmConfig.security.sudo.wheelNeedsPassword;
      ssh = vmConfig.services.openssh.settings;
      firewall = {inherit (vmConfig.networking.firewall) enable allowedTCPPorts allowedUDPPorts;};
      browser = vmConfig.programs.firefox.policies;
      rootFilesystem = vmConfig.virtualisation.fileSystems."/";
      drives = vmConfig.virtualisation.qemu.drives;
      qemuOptions =
        builtins.filter (
          option:
            !(lib.hasPrefix "-kernel " option || lib.hasPrefix "-initrd " option || lib.hasPrefix "-append " option)
        )
        vmConfig.virtualisation.qemu.options;
      network =
        builtins.replaceStrings [(lib.getExe vmConfig.virtualisation.host.pkgs.passt)] ["<passt>"]
        (lib.concatStringsSep " " vmConfig.virtualisation.qemu.networkingOptions);
      packages = map lib.getName vmConfig.environment.systemPackages;
    };
  };
}
