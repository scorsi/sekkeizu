# GitHub CLI. Git operations go through SSH (the FIDO2 key), not HTTPS tokens.
{
  flake.modules.homeManager.github = {
    programs.gh = {
      enable = true;
      settings = {
        git_protocol = "ssh";
        prompt = "enabled";
      };
    };
  };
}
