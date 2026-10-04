{pkgs, ...}: {
  # Desktop applications connect through host display and SSH services.
  services.xserver.enable = false;

  programs.firefox = {
    enable = true;
    policies = {
      DisableTelemetry = true;
      Preferences = {
        # 让 Firefox 自己画标题栏按钮
        "browser.tabs.inTitlebar" = 1;
      };
    };
  };

  environment.etc."xdg/gtk-3.0/settings.ini".text = ''
    [Settings]
    gtk-theme-name=Breeze
    gtk-decoration-layout=:minimize,maximize,close
  '';

  environment.etc."xdg/gtk-4.0/settings.ini".text = ''
    [Settings]
    gtk-theme-name=Breeze
    gtk-decoration-layout=:minimize,maximize,close
  '';
  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-cjk-serif
    noto-fonts-color-emoji
  ];
}
