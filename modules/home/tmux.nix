# tmux, carried over from dev-configs. On the server, this is what keeps sessions
# alive when the SSH connection drops: `tmux new -A -s main` to (re)join.
{
  flake.modules.homeManager.tmux =
    { pkgs, ... }:
    {
      programs.tmux = {
        enable = true;
        prefix = "C-Space";
        mouse = true;
        keyMode = "vi";
        baseIndex = 1; # windows and panes numbered from 1
        terminal = "tmux-256color";
        escapeTime = 10;

        # Plugins from nixpkgs (no more TPM); theme comes from catppuccin.
        plugins = with pkgs.tmuxPlugins; [
          sensible
          vim-tmux-navigator
        ];

        extraConfig = ''
          set -sa terminal-overrides ",xterm*:Tc"
          set -g renumber-windows on

          bind r source-file ~/.config/tmux/tmux.conf \; display "Reloaded!"

          bind-key -T prefix h split-window -v -c "#{pane_current_path}"
          bind-key -T prefix v split-window -h -c "#{pane_current_path}"
          bind-key -T prefix x kill-pane

          is_vim="ps -o state= -o comm= -t '#{pane_tty}' \
              | grep -iqE '^[^TXZ ]+ +(\\S+\\/)?g?(view|l?n?vim?x?|fzf)(diff)?$'"
          bind-key -n M-Left if-shell "$is_vim" 'send-keys M-Left' 'select-pane -L'
          bind-key -n M-Down if-shell "$is_vim" 'send-keys M-Down' 'select-pane -D'
          bind-key -n M-Up if-shell "$is_vim" 'send-keys M-Up' 'select-pane -U'
          bind-key -n M-Right if-shell "$is_vim" 'send-keys M-Right' 'select-pane -R'
        '';
      };
    };
}
