{
  pkgs,
  cachyos-kernel,
  ...
}: {
  boot.kernelPackages = cachyos-kernel.legacyPackages.${pkgs.stdenv.hostPlatform.system}.linuxPackages-cachyos-bore-x86_64-v3;
  boot.kernelModules = ["virtio_gpu"];
  hardware.graphics.enable = true;
}
