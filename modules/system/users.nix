{vmSettings, ...}: {
  users.mutableUsers = vmSettings.security.mutableUsers;
  users.users.${vmSettings.user} = {
    isNormalUser = true;
    extraGroups = vmSettings.security.extraGroups;
    initialPassword = vmSettings.security.initialPassword;
  };

  security.sudo.wheelNeedsPassword = vmSettings.security.wheelNeedsPassword;
}
