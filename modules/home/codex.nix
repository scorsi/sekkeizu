# OpenAI Codex CLI. Package only: login is interactive (`codex login`), no declared config.
{
  flake.modules.homeManager.codex = {
    programs.codex.enable = true;
  };
}
