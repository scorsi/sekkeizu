# tmux, repris de dev-configs. Sur le serveur, c'est ce qui garde les sessions
# vivantes quand la connexion SSH tombe : `tmux new -A -s main` pour (re)joindre.
{
  flake.modules.homeManager.tmux =
    { pkgs, ... }:
    {
      programs.tmux = {
        enable = true;
        prefix = "C-Space";
        mouse = true;
        keyMode = "vi";
        baseIndex = 1; # fenêtres et panneaux numérotés à partir de 1
        terminal = "tmux-256color";
        escapeTime = 10;

        # Plugins depuis nixpkgs (plus de TPM) ; le thème vient de catppuccin.
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
