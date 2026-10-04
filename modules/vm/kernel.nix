{
  pkgs,
  cachyos-kernel,
  vmSettings,
  ...
}: {
  boot.kernelPackages =
    (
      if vmSettings.kernel.source == "cachyos"
      then cachyos-kernel.legacyPackages.${pkgs.stdenv.hostPlatform.system}
      else pkgs
    ).${
      vmSettings.kernel.package
    };
  boot.kernelModules = ["virtio_gpu"];
  hardware.graphics.enable = true;
}
