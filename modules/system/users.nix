{vmSettings, ...}: {
  users.mutableUsers = false;
  users.users.${vmSettings.user} = {
    isNormalUser = true;
    extraGroups = ["wheel" "render" "video"];
    initialPassword = "change-me";
  };

  security.sudo.wheelNeedsPassword = false;
}
