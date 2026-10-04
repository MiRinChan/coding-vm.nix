{
  pkgs,
  lib,
  vmSettings,
  ...
}: {
  services.openssh = {
    enable = true;
    settings = vmSettings.security.ssh;
  };

  # Install the host-generated public key before sshd is used.
  # /tmp/shared is provided by the NixOS qemu-vm module and points to $SHARED_DIR from run-vm.
  systemd.services.install-host-ssh-key = {
    description = "Install SSH public key passed from host launcher";
    wantedBy = ["multi-user.target"];
    before = ["sshd.service"];
    after = ["local-fs.target"];
    path = [pkgs.coreutils];
    serviceConfig.Type = "oneshot";
    script = ''
      install -d -m 700 -o ${vmSettings.user} -g users /home/${vmSettings.user}/.ssh

      if [ -s /tmp/shared/authorized_keys ]; then
        install -m 600 -o ${vmSettings.user} -g users \
          /tmp/shared/authorized_keys \
          /home/${vmSettings.user}/.ssh/authorized_keys
      fi
    '';
  };
}
