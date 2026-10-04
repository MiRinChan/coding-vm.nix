{
  lib,
  vmSettings,
  ...
}:
lib.mkIf vmSettings.spoofSettings.enable {
  # Locale, timezone, keyboard, paper size, and application region hints.
  time.timeZone = vmSettings.spoofSettings.region.timeZone;

  i18n.defaultLocale = vmSettings.spoofSettings.region.locale;

  console.keyMap = "us";

  environment.variables = {
    LANGUAGE = "en_US:en";
    PAPERSIZE = "letter";
  };

  location = {
    provider = "manual";
    latitude = vmSettings.spoofSettings.region.latitude;
    longitude = vmSettings.spoofSettings.region.longitude;
  };

  services.geoclue2 = {
    enable = true;
    enableStatic = true;
    staticLatitude = vmSettings.spoofSettings.region.latitude;
    staticLongitude = vmSettings.spoofSettings.region.longitude;
    staticAltitude = 10;
    staticAccuracy = 50000;

    enableWifi = false;
    enable3G = false;
    enableCDMA = false;
    enableModemGPS = false;
    enableNmea = false;
    submitData = false;

    appConfig.firefox = {
      isAllowed = true;
      isSystem = false;
      users = [];
    };
  };
  programs.firefox.policies.Preferences = {
    "intl.accept_languages" = "en-US,en";
    "browser.search.region" = "US";
    "browser.region.network.url" = "";
    "browser.region.update.enabled" = false;
    "geo.enabled" = true;
  };
}
