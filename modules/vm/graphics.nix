{
  lib,
  vmSettings,
  ...
}: {
  virtualisation = {
    qemu.forceAccel = true;
    qemu.options = lib.mkAfter [
      "-cpu host"
      "-object iothread,id=root-io"
      "-vga none"
      "-device virtio-gpu-gl-pci"
      "-display egl-headless,rendernode=${vmSettings.gpu.renderNode}"
    ];
    # EGL renders through the host GPU without a display window.
    graphics = false;
  };
}
