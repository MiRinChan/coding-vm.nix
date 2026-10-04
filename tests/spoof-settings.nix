let
  flake = builtins.getFlake (toString ../.);
  settings = import ../settings.nix;
  lib = flake.inputs.nixpkgs.lib;
  makeConfig = enable:
    (lib.nixosSystem {
      system = settings.system;
      specialArgs = {
        inherit (flake.inputs) nixpkgs cachyos-kernel;
        vmSettings =
          settings
          // {
            spoofSettings = settings.spoofSettings // {inherit enable;};
          };
      };
      modules = [../hosts/coding-vm.nix];
    }).config;
  on = makeConfig true;
  off = makeConfig false;
  onNetwork = lib.concatStringsSep " " on.virtualisation.qemu.networkingOptions;
  offNetwork = lib.concatStringsSep " " off.virtualisation.qemu.networkingOptions;
in
  assert on.time.timeZone == settings.spoofSettings.region.timeZone;
  assert on.services.geoclue2.enable && on.services.geoclue2.enableStatic;
  assert on.location.latitude == settings.spoofSettings.region.latitude;
  assert on.programs.firefox.policies.Preferences."browser.search.region" == "US";
  assert lib.hasInfix "outbound-if4=tailscale0" onNetwork;
  assert lib.hasInfix "outbound-if6=tailscale0" onNetwork;
  assert !off.services.geoclue2.enable;
  assert off.time.timeZone != settings.spoofSettings.region.timeZone;
  assert !(off.environment.variables ? PAPERSIZE);
  assert !(off.programs.firefox.policies.Preferences ? "browser.search.region");
  assert lib.hasInfix "-netdev user," offNetwork;
  assert lib.hasInfix "hostfwd=tcp:127.0.0.1:" offNetwork;
  assert !(lib.hasInfix "tailscale0" offNetwork);
  assert on.virtualisation.diskSize == off.virtualisation.diskSize; true
