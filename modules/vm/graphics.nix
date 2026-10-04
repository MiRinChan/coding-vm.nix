{
  lib,
  vmSettings,
  ...
}: {
  virtualisation = {
    qemu.forceAccel = true;
    qemu.options = lib.mkAfter [
      "-cpu host"
      "-monitor none"
      ''-chardev socket,id=console,path="$VM_CONSOLE_SOCKET",server=on,wait=off,logfile="$VM_CONSOLE_LOG",logappend=on''
      "-serial chardev:console"
      ''-qmp unix:"$VM_QMP_SOCKET",server=on,wait=off''
      ''-pidfile "$VM_PID_FILE"''
      "-object iothread,id=root-io"
      "-vga none"
      "-device virtio-gpu-gl-pci"
      "-display egl-headless,rendernode=${vmSettings.gpu.renderNode}"
    ];
    # EGL renders through the host GPU without a display window.
    graphics = false;
  };
}
