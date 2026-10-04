{
  pkgs,
  lib,
  nixpkgs,
  ...
}: {
  system.stateVersion = "25.11";
  nix.settings.experimental-features = ["nix-command" "flakes"];

  # Make `nix shell nixpkgs#...` resolve to this flake's nixpkgs input
  # instead of fetching https://channels.nixos.org/flake-registry.json.
  nix.registry.nixpkgs.flake = nixpkgs;
  nix.settings.nix-path = ["nixpkgs=${nixpkgs}"];

  # vscode and claude-code are unfree packages in nixpkgs.
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [
      "vscode"
      "claude-code"
    ];
}
