# Secrets with an end date (tokens, certificates): declared next to the feature that uses them,
# reminded on jiban as the date approaches (modules/macos/secret-reminders.nix).
{ lib, ... }:
{
  options.sekkeizu.expiringSecrets = lib.mkOption {
    default = { };
    description = "Secrets that expire, by name.";
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          expires = lib.mkOption {
            type = lib.types.strMatching "[0-9]{4}-[0-9]{2}-[0-9]{2}";
            description = "Expiry date (YYYY-MM-DD, UTC).";
          };
          renew = lib.mkOption {
            type = lib.types.str;
            description = "How to renew it, shown in the reminder.";
          };
        };
      }
    );
  };
}
