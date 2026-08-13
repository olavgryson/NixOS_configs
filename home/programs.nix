################################################################################
#  Configured programs — git, bash, terminal, shell QoL.
################################################################################
{ pkgs, ... }:
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
      rebuild = "sudo nixos-rebuild switch --flake ~/nixos-config#dragonflyg4";
    };
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
      confirm_os_window_close = 0;        # no "are you sure" on close
      tab_title_template = "{index}";     # removes user@hostname from tab bar
      copy_on_select = "clipboard";
      open_url_modifiers = "none";        # plain click on a URL opens it
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
