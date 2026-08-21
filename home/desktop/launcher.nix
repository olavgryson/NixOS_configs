################################################################################
#  App launcher (rofi) + Wi-Fi picker.
#
#  Colours are NOT baked here: every rofi invocation passes
#  -theme ~/.config/theme/rofi.rasi, a copy of the currently selected palette
#  maintained by ./theme-switch.nix — so the launcher recolours live on a
#  theme switch instead of waiting for a rebuild.
################################################################################
{ pkgs, lib, config, ... }:

let
  homeDir = config.home.homeDirectory;
in
{
  #### App launcher ($mod+Space) #############################################
  # rofi comes from programs.rofi rather than home.packages, so its config is
  # part of the rebuild instead of the built-in "Default" theme.
  programs.rofi = {
    enable = true;
    terminal = "${pkgs.kitty}/bin/kitty";
    font = "JetBrainsMono Nerd Font 11";

    extraConfig = {
      modes = "drun,run,window";
      show-icons = true;
      # Only the program name, not "Name (generic description)".
      drun-display-format = "{name}";
      icon-theme = "Papirus-Dark";
      display-drun = "  apps";
      display-run = "  run";
      display-window = "  windows";
      kb-cancel = "Escape,Super+space";
    };
    # No module-level `theme`: the runtime copy is selected per invocation via
    # -theme (see $menu in wm.nix and the callers below).
  };

  # Wi-Fi picker for the waybar `network` module: lists nearby networks and
  # saved connections, prompts for the passphrase via rofi. The package
  # defaults to dmenu; this pins it to rofi with the runtime theme, like every
  # other caller. Its "Edit connections…" entry still opens
  # nm-connection-editor (hence networkmanagerapplet stays installed).
  xdg.configFile."networkmanager-dmenu/config.ini".text = ''
    [dmenu]
    dmenu_command = rofi -theme ${homeDir}/.config/theme/rofi.rasi
  '';
}
