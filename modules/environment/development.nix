{
  pkgs,
  lib,
  vmSettings,
  ...
}: {
  # VS Code Remote-SSH downloads a prebuilt server binary.
  # On NixOS, nix-ld provides the FHS dynamic linker path it expects.
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      stdenv.cc.cc
      zlib
      openssl
      curl
      icu
      libxml2
      util-linux
      nss
      nspr
      expat
      libsecret
      krb5
    ];
  };
  # Development tools and coding clients.
  environment.systemPackages = map (name: lib.getAttrFromPath (lib.splitString "." name) pkgs) vmSettings.software.packages;
}
