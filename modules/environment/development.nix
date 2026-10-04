{pkgs, ...}: {
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
  environment.systemPackages = with pkgs; [
    bashInteractive
    binutils
    ripgrep
    jq
    gnused
    gnugrep
    findutils
    curl
    dnsutils
    git
    iproute2
    nftables
    pciutils
    mesa-demos
    wget
    waypipe

    vscode
    claude-code
    kitty
    xauth
    gh
    nodejs
    mcp-nixos
    python3
  ];
}
