{
  defaultsVersion = 1;
  systemStateVersion = "25.11";
  system = "x86_64-linux";
  user = "alice";
  hostName = "coding-vm";
  resources = {
    cores = 8;
    memoryMiB = 16 * 1024;
    diskMiB = 80 * 1024;
    preallocateDisk = false;
  };
  storage = {
    writableStore = true;
    writableStoreUseTmpfs = true;
    autoResize = true;
    rootOptions = ["noatime"];
    cache = "none";
    aio = "native";
    discard = "ignore";
    writeError = "report";
    scheduler = "none";
  };
  kernel = {
    source = "cachyos";
    package = "linuxPackages-cachyos-bore-x86_64-v3";
  };
  security = {
    mutableUsers = false;
    extraGroups = ["wheel" "render" "video"];
    initialPassword = "change-me";
    wheelNeedsPassword = false;
    ssh = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      PubkeyAuthentication = true;
      X11Forwarding = true;
      X11UseLocalhost = true;
    };
  };
  launcher = {
    sshAlias = "coding-vm";
    sshPort = 2223;
    sshKey = null;
    fsMountDir = null;
    fsRemote = null;
    openVSCode = true;
    openKitty = true;
    mountSSHFS = true;
    sshTimeoutSeconds = 900;
    nofileLimit = 2097152;
    networkGuardIntervalSeconds = 2;
  };
  software = {
    packages = [
      "bashInteractive"
      "binutils"
      "ripgrep"
      "jq"
      "gnused"
      "gnugrep"
      "findutils"
      "curl"
      "dnsutils"
      "git"
      "iproute2"
      "nftables"
      "pciutils"
      "mesa-demos"
      "wget"
      "waypipe"
      "vscode"
      "claude-code"
      "kitty"
      "xauth"
      "gh"
      "nodejs"
      "mcp-nixos"
      "python3"
    ];
    fonts = ["noto-fonts" "noto-fonts-cjk-sans" "noto-fonts-cjk-serif" "noto-fonts-color-emoji"];
    allowedUnfree = ["vscode" "claude-code"];
    firefox = true;
  };
  gpu.renderNode = "/dev/dri/renderD128";
  # Optional region and Tailscale egress preset.
  # The selected exit node determines the public IP address.
  spoofSettings = {
    enable = true;
    network = {
      interface = "tailscale0";
      ipv4 = "10.0.2.15";
      ipv6 = "fd00:2::15";
      gateway4 = "10.0.2.2";
      gateway6 = "fd00:2::2";
      dns4 = "1.1.1.1";
      dns6 = "2606:4700:4700::1111";
    };
    region = {
      timeZone = "America/Los_Angeles";
      locale = "en_US.UTF-8";
      consoleKeyMap = "us";
      language = "en_US:en";
      paperSize = "letter";
      browserLanguages = "en-US,en";
      browserRegion = "US";
      altitude = 10;
      accuracy = 50000;
      latitude = 37.7749;
      longitude = -122.4194;
    };
  };
}
