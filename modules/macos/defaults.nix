# Réglages macOS (équivalents de System Settings), appliqués à chaque switch.
# Ce que nix-darwin ne couvre pas : `system.defaults.CustomUserPreferences`.
{
  flake.modules.darwin.defaults = {
    system.defaults = {
      NSGlobalDomain = {
        AppleShowAllExtensions = true;
        ApplePressAndHoldEnabled = false; # répétition de touche au lieu des accents
        NSDocumentSaveNewDocumentsToCloud = false;
      };

      finder = {
        AppleShowAllFiles = true;
        ShowPathbar = true;
        FXPreferredViewStyle = "Nlsv"; # vue liste
        FXEnableExtensionChangeWarning = false;
      };

      dock = {
        autohide = true;
        show-recents = false;
      };

      # Serveur : les mises à jour de macOS se font à la main, après un switch de test.
      SoftwareUpdate.AutomaticallyInstallMacOSUpdates = false;

      # Pas de fichiers .DS_Store sur les volumes réseau et USB (disque externe).
      CustomUserPreferences."com.apple.desktopservices" = {
        DSDontWriteNetworkStores = true;
        DSDontWriteUSBStores = true;
      };
    };
  };
}
