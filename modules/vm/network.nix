{
  config,
  lib,
  vmSettings,
  ...
}: {
  virtualisation.qemu.networkingOptions = lib.mkForce (
    if vmSettings.spoofSettings.enable
    then [
      (lib.concatStringsSep "," [
        "-netdev passt,id=host0"
        "path=${lib.getExe config.virtualisation.host.pkgs.passt}"
        "interface=${vmSettings.spoofSettings.network.interface}"
        "outbound-if4=${vmSettings.spoofSettings.network.interface}"
        "outbound-if6=${vmSettings.spoofSettings.network.interface}"
        "param=--address=${vmSettings.spoofSettings.network.ipv4}"
        "param=--address=${vmSettings.spoofSettings.network.ipv6}"
        "param=--netmask=24"
        "param=--gateway=${vmSettings.spoofSettings.network.gateway4}"
        "param=--gateway=${vmSettings.spoofSettings.network.gateway6}"
        "param=--dns=${vmSettings.spoofSettings.network.dns4}"
        "param=--dns=${vmSettings.spoofSettings.network.dns6}"
        "param=--no-map-gw"
        "param=--udp-ports=none"
        "param=--no-dhcp-search"
        "param=--hostname=${vmSettings.hostName}"
        "tcp-ports=127.0.0.1/\${VM_SSH_PORT:-2223}:22"
      ])
      "-device virtio-net-pci,netdev=host0,mac=52:54:00:12:34:56"
    ]
    else [
      "-netdev user,id=host0,ipv6=on,hostfwd=tcp:127.0.0.1:\${VM_SSH_PORT:-2223}-:22"
      "-device virtio-net-pci,netdev=host0,mac=52:54:00:12:34:56"
    ]
  );
  networking = {
    hostName = vmSettings.hostName;
    useDHCP = lib.mkDefault true;
    enableIPv6 = true;

    firewall.enable = true;
    firewall.allowedTCPPorts = [22];
  };
}
