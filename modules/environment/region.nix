{
  lib,
  vmSettings,
  ...
}:
lib.mkIf vmSettings.spoofSettings.enable {
  # Locale, timezone, keyboard, paper size, and application region hints.
  time.timeZone = vmSettings.spoofSettings.region.timeZone;

  i18n.defaultLocale = vmSettings.spoofSettings.region.locale;

  console.keyMap = vmSettings.spoofSettings.region.consoleKeyMap;

  environment.variables = {
    LANGUAGE = vmSettings.spoofSettings.region.language;
    PAPERSIZE = vmSettings.spoofSettings.region.paperSize;
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
    staticAltitude = vmSettings.spoofSettings.region.altitude;
    staticAccuracy = vmSettings.spoofSettings.region.accuracy;

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
    "intl.accept_languages" = vmSettings.spoofSettings.region.browserLanguages;
    "browser.search.region" = vmSettings.spoofSettings.region.browserRegion;
    "browser.region.network.url" = "";
    "browser.region.update.enabled" = false;
    "geo.enabled" = true;
  };
}
