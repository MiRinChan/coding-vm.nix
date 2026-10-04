{
  pkgs,
  lib,
  vmSettings,
  ...
}: let
  # Upstream TCP logs bind failures and continues. Stop instead of leaking.
  exitNodePasst = pkgs.passt.overrideAttrs (old: {
    patches = (old.patches or []) ++ [../../patches/passt-bind-fail.patch];
  });

  hostVirtiofsd = pkgs.writeShellApplication {
    name = "virtiofsd";
    text = ''
      # Avoid inode prefetch across the entire host store during directory scans.
      args=()
      store_share=0
      for arg in "$@"; do
        case "$arg" in
          --shared-dir=/nix/store) store_share=1 ;;
        esac
      done
      for arg in "$@"; do
        if [ "$store_share" -eq 1 ] && [ "$arg" = --cache=always ]; then
          args+=(--cache=auto --no-readdirplus)
        else
          args+=("$arg")
        fi
      done
      exec ${lib.getExe pkgs.virtiofsd} "''${args[@]}" --rlimit-nofile=2097152
    '';
  };
in {
  # Only the host runner uses this wrapper. Guest packages stay unchanged.
  virtualisation.host.pkgs =
    pkgs
    // {
      virtiofsd = hostVirtiofsd;
      passt =
        if vmSettings.spoofSettings.enable
        then exitNodePasst
        else pkgs.passt;
    };
}
