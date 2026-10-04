{
  system = "x86_64-linux";
  user = "alice";
  hostName = "coding-vm";
  resources = {
    cores = 8;
    memoryMiB = 16 * 1024;
    diskMiB = 80 * 1024;
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
      latitude = 37.7749;
      longitude = -122.4194;
    };
  };
}
