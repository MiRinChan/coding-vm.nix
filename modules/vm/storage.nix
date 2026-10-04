{
  lib,
  vmSettings,
  ...
}: {
  virtualisation = {
    cores = vmSettings.resources.cores;
    memorySize = vmSettings.resources.memoryMiB;
    diskSize = vmSettings.resources.diskMiB;
    writableStore = vmSettings.storage.writableStore;
    writableStoreUseTmpfs = vmSettings.storage.writableStoreUseTmpfs;

    fileSystems."/" = {
      autoResize = vmSettings.storage.autoResize;
      options = vmSettings.storage.rootOptions;
    };
    qemu.drives = lib.mkForce [
      {
        name = "root";
        file = ''"$NIX_DISK_IMAGE"'';
        driveExtraOpts = {
          format = "qcow2";
          cache = vmSettings.storage.cache;
          aio = vmSettings.storage.aio;
          discard = vmSettings.storage.discard;
          werror = vmSettings.storage.writeError;
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
    ACTION=="add|change", SUBSYSTEM=="block", KERNEL=="vd[a-z]", ATTR{queue/scheduler}="${vmSettings.storage.scheduler}"
  '';
}
