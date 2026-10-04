{
  lib,
  vmSettings,
  ...
}: {
  virtualisation = {
    cores = vmSettings.resources.cores;
    memorySize = vmSettings.resources.memoryMiB;
    diskSize = vmSettings.resources.diskMiB;
    writableStore = true;
    writableStoreUseTmpfs = true;

    fileSystems."/" = {
      autoResize = true;
      options = ["noatime"];
    };
    qemu.drives = lib.mkForce [
      {
        name = "root";
        file = ''"$NIX_DISK_IMAGE"'';
        driveExtraOpts = {
          format = "qcow2";
          cache = "none";
          aio = "native";
          discard = "ignore";
          werror = "report";
        };
        deviceExtraOpts = {
          bootindex = "1";
          serial = "root";
          iothread = "root-io";
          "num-queues" = toString vmSettings.resources.cores;
        };
      }
    ];
  };
  # Avoid a second I/O scheduler above the host's storage scheduler.
  services.udev.extraRules = ''
    ACTION=="add|change", SUBSYSTEM=="block", KERNEL=="vd[a-z]", ATTR{queue/scheduler}="none"
  '';
}
