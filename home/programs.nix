################################################################################
#  Configured programs — git, bash, terminal, shell QoL.
################################################################################
{ pkgs, lib, ... }:
{
  #### Git ###################################################################
  programs.git = {
    enable = true;
    settings = {
      user.name = "Olav Gryson";
      user.email = "olav.gryson@gmail.com";
      init.defaultBranch = "main";
    };
  };

  # Tools installed outside Nix (uv, pipx, npm --global) drop their entry
  # points in ~/.local/bin, which is on no default NixOS path.
  home.sessionPath = [ "$HOME/.local/bin" ];

  #### Shell (keeps bash, adds modern helpers) ################################
  programs.bash = {
    enable = true;
    initExtra = ''
      PS1='\[\e[38;5;43m\]\w\[\e[0m\] \$ '
    '';
    shellAliases = {
      ll = "eza -la --git";
      cat = "bat -pp";
      clauded = "claude --dangerously-skip-permissions";
      agyd = "agy --dangerously-skip-permissions";
      freebuff = "~/.config/manicode/freebuff";
      # Uses the school Copilot token (COPILOT_GITHUB_TOKEN) for this shell;
      # token itself lives in ~/.config/environment.d/10-copilot.conf, not here.
      copilotschool = "export $(cat ~/.config/environment.d/10-copilot.conf); copilot";
      # Isolated OpenCode profile for school with slug resolution (~/.local/bin/opencodeSchool)
      opencodeschool = "opencodeSchool";
      ta = "tmux attach || tmux new";
    };
  };
  #### Agent multiplexer (herdr) #############################################
  # Terminal multiplexer for running and watching multiple AI coding agents.
  # TUI only — the desktop entry below makes it launchable from rofi.
  programs.herdr = {
    enable = true;
    settings =
      let
        azertyChars = [ "&" "é" "\"" "'" "(" "§" "è" "!" "ç" "à" ];
        tabCommand = isDirect: idx: char: {
          key = if isDirect then "alt+${char}" else "prefix+${char}";
          type = "shell";
          command = "herdr-focus-tab ${toString idx}";
          description = "jump to tab ${toString (idx + 1)}${if isDirect then " (direct)" else ""}";
        };
      in {
        onboarding = false;
        ui.agent_panel_sort = "spaces";
        keys = {
          prefix = "ctrl+<";
          command = (lib.imap0 (tabCommand false) azertyChars)
                 ++ (lib.imap0 (tabCommand true) azertyChars);
        };
      };
  };

  # Launcher entry: herdr has no .desktop of its own (terminal-only app).
  xdg.desktopEntries."herdr" = {
    name = "Herdr";
    comment = "Agent multiplexer";
    exec = "kitty herdr";
    terminal = false;
    categories = [ "System" ];
  };

  #### Terminal multiplexer (tmux) ###########################################
  programs.tmux = {
    enable = true;
    mouse = true;
    baseIndex = 1;
    escapeTime = 10;
    historyLimit = 10000;
    terminal = "tmux-256color";
    # Belgian AZERTY window navigation (matches Kitty and Herdr)
    extraConfig = ''
      # Top-row unshifted keys on Belgian AZERTY (& é " ' ( § è ! ç à) for windows 1..10
      bind-key & select-window -t 1
      bind-key é select-window -t 2
      bind-key '"' select-window -t 3
      bind-key \' select-window -t 4
      bind-key ( select-window -t 5
      bind-key § select-window -t 6
      bind-key è select-window -t 7
      bind-key ! select-window -t 8
      bind-key ç select-window -t 9
      bind-key à select-window -t 10

      # Direct Alt+number navigation (matching Kitty and Herdr)
      bind-key -n M-& select-window -t 1
      bind-key -n M-é select-window -t 2
      bind-key -n 'M-"' select-window -t 3
      bind-key -n "M-'" select-window -t 4
      bind-key -n M-( select-window -t 5
      bind-key -n M-§ select-window -t 6
      bind-key -n M-è select-window -t 7
      bind-key -n M-! select-window -t 8
      bind-key -n M-ç select-window -t 9
      bind-key -n M-à select-window -t 10
    '';
  };

  programs.zoxide.enable = true;
  programs.fzf.enable = true;

  #### Terminal (provides the kitty package too) #############################
  programs.kitty = {
    enable = true;
    settings = {
      font_family = "JetBrainsMono Nerd Font";
      font_size = 10;
      background_opacity = "0.95";
      window_padding_width = 6;
      scrollback_lines = 10000;
      enable_audio_bell = false;
      remember_window_size = false;
      confirm_os_window_close = 0;        # no "are you sure" on close
      tab_title_template = "{index}";     # removes user@hostname from tab bar
      copy_on_select = "clipboard";
      tab_bar_edge = "top";
      tab_bar_style = "powerline";
      # "splits" must be enabled, otherwise the vsplit/hsplit binds do nothing.
      enabled_layouts = "splits,stack";
    };

    keybindings = {
      # Splits inside a single window.
      "ctrl+shift+enter" = "launch --location=vsplit --cwd=current";
      "ctrl+shift+d" = "launch --location=hsplit --cwd=current";
      "alt+left" = "neighboring_window left";
      "alt+right" = "neighboring_window right";
      "alt+up" = "neighboring_window up";
      "alt+down" = "neighboring_window down";
      "ctrl+shift+z" = "toggle_layout stack";   # fullscreen the active split

      # Jump straight to a tab. NOTE: on Belgian AZERTY the unshifted number
      # row gives & é " ' ( § è ! ç à, so `alt+1` would require Shift. Bind on
      # the characters the keys actually produce instead.
      "alt+ampersand" = "goto_tab 1";
      "alt+eacute" = "goto_tab 2";
      "alt+quotedbl" = "goto_tab 3";
      "alt+apostrophe" = "goto_tab 4";
      "alt+parenleft" = "goto_tab 5";
      "alt+section" = "goto_tab 6";
      "alt+egrave" = "goto_tab 7";
      "alt+exclam" = "goto_tab 8";
      "alt+ccedilla" = "goto_tab 9";
      "alt+agrave" = "goto_tab 10";
    };
  };
}
