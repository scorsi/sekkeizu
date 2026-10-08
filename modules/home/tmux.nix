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
        plugins = with pkgs.tmuxPlugins; [ sensible ];

        extraConfig = ''
          set -sa terminal-overrides ",xterm*:Tc"
          set -g renumber-windows on

          bind r source-file ~/.config/tmux/tmux.conf \; display "Reloaded!"

          bind-key -T prefix h split-window -v -c "#{pane_current_path}"
          bind-key -T prefix v split-window -h -c "#{pane_current_path}"
          bind-key -T prefix x kill-pane

          # smart-splits.nvim sets @pane-is-vim on the pane while Neovim runs, so
          # navigation (C-hjkl) and resizing (M-hjkl) cross the Neovim/tmux boundary.
          bind-key -n C-h if -F "#{@pane-is-vim}" 'send-keys C-h' 'select-pane -L'
          bind-key -n C-j if -F "#{@pane-is-vim}" 'send-keys C-j' 'select-pane -D'
          bind-key -n C-k if -F "#{@pane-is-vim}" 'send-keys C-k' 'select-pane -U'
          bind-key -n C-l if -F "#{@pane-is-vim}" 'send-keys C-l' 'select-pane -R'

          bind-key -n M-Left if -F "#{@pane-is-vim}" 'send-keys M-Left' 'select-pane -L'
          bind-key -n M-Down if -F "#{@pane-is-vim}" 'send-keys M-Down' 'select-pane -D'
          bind-key -n M-Up if -F "#{@pane-is-vim}" 'send-keys M-Up' 'select-pane -U'
          bind-key -n M-Right if -F "#{@pane-is-vim}" 'send-keys M-Right' 'select-pane -R'

          bind-key -n M-h if -F "#{@pane-is-vim}" 'send-keys M-h' 'resize-pane -L 3'
          bind-key -n M-j if -F "#{@pane-is-vim}" 'send-keys M-j' 'resize-pane -D 3'
          bind-key -n M-k if -F "#{@pane-is-vim}" 'send-keys M-k' 'resize-pane -U 3'
          bind-key -n M-l if -F "#{@pane-is-vim}" 'send-keys M-l' 'resize-pane -R 3'

          bind-key -T copy-mode-vi C-h select-pane -L
          bind-key -T copy-mode-vi C-j select-pane -D
          bind-key -T copy-mode-vi C-k select-pane -U
          bind-key -T copy-mode-vi C-l select-pane -R
        '';
      };
    };
}
