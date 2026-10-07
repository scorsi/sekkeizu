# macOS settings (System Settings equivalents), applied on every switch.
# What nix-darwin doesn't cover: `system.defaults.CustomUserPreferences`.
{
  flake.modules.darwin.defaults = {
    system.defaults = {
      NSGlobalDomain = {
        AppleShowAllExtensions = true;
        ApplePressAndHoldEnabled = false; # key repeat instead of accent picker
        NSDocumentSaveNewDocumentsToCloud = false;
      };

      finder = {
        AppleShowAllFiles = true;
        ShowPathbar = true;
        FXPreferredViewStyle = "Nlsv"; # list view
        FXEnableExtensionChangeWarning = false;
      };

      dock = {
        autohide = true;
        show-recents = false;
      };

      # Server: macOS updates are done by hand, after a test switch.
      SoftwareUpdate.AutomaticallyInstallMacOSUpdates = false;

      # No .DS_Store files on network and USB volumes (external drive).
      CustomUserPreferences."com.apple.desktopservices" = {
        DSDontWriteNetworkStores = true;
        DSDontWriteUSBStores = true;
      };
    };
  };
}
