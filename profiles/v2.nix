let
  previous = import ./v1.nix;
in
  previous
  // {
    defaultsVersion = 2;
    launcher =
      previous.launcher
      // {
        openVSCode = false;
        openKitty = false;
      };
  }
