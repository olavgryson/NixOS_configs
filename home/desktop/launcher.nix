################################################################################
#  App launcher (rofi) + bellotto theme + Wi-Fi picker.
################################################################################
{ pkgs, lib, config, ... }:

let
  theme = import ../../theme.nix { };
  inherit (theme) raw;

in
{
  #### App launcher ($mod+Space) #############################################
  # rofi comes from programs.rofi rather than home.packages, so its config and
  # theme are part of the rebuild instead of the built-in "Default" theme.
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

    # Name only; the file itself is written below into
    # ~/.local/share/rofi/themes/, the directory rofi (and home-manager) search.
    #
    # Why not `theme = pkgs.writeText ...`? The rofi module uses `isAttrs` to
    # detect a theme-as-attrset, and a derivation IS an attrset. It then tries
    # to serialise it as rasi and dies with "Unhandled value type set".
    theme = "bellotto";
  };

  # .rasi wants #rrggbbaa, so the bare hex from ../theme.nix again.
  xdg.dataFile."rofi/themes/bellotto.rasi".text = ''
    * {
      bg:       #${raw.ink}f2;
      bg-alt:   #${raw.surface}b3;
      fg:       #${raw.text}ff;
      fg-dim:   #${raw.subtle}ff;
      accent:   #${raw.sky}ff;
      gold:     #${raw.ochre}ff;
      edge:     #${raw.haze}59;
      urgent:   #${raw.alarm}ff;

      background-color: transparent;
      text-color:       @fg;
      font:             "JetBrainsMono Nerd Font 11";
    }

    window {
      transparency:     "real";
      location:         center;
      anchor:           center;
      width:            640px;
      border:           2px;
      border-radius:    14px;
      border-color:     @edge;
      background-color: @bg;
      padding:          0;
      children:         [ mainbox ];
    }

    mainbox {
      padding:  16px;
      spacing:  12px;
      children: [ inputbar, listview ];
    }

    /* Search bar: the same rounded area as the clock in waybar. */
    inputbar {
      spacing:          10px;
      padding:          10px 14px;
      border-radius:    10px;
      background-color: @bg-alt;
      children:         [ prompt, entry ];
    }
    prompt {
      text-color:     @gold;
      vertical-align: 0.5;
    }
    entry {
      placeholder:       "Search…";
      placeholder-color: @fg-dim;
      vertical-align:    0.5;
    }

    listview {
      columns:      1;
      lines:        9;
      scrollbar:    false;
      fixed-height: false;
      spacing:      2px;
    }

    element {
      padding:       8px 12px;
      spacing:       12px;
      border-radius: 8px;
    }
    element normal.normal,
    element alternate.normal { text-color: @fg; }
    element normal.urgent,
    element alternate.urgent { text-color: @urgent; }

    /* Selected row = the sky, with the dark foreground as text. Same
       inversion as the active workspace in waybar. */
    element selected.normal {
      background-color: @accent;
      text-color:       #${raw.ink}ff;
    }
    element selected.urgent {
      background-color: @urgent;
      text-color:       #${raw.ink}ff;
    }

    element-icon {
      size:           24px;
      vertical-align: 0.5;
    }
    element-text {
      vertical-align: 0.5;
      text-color:     inherit;
    }
  '';

  # Wi-Fi picker for the waybar `network` module: lists nearby networks and
  # saved connections, prompts for the passphrase via rofi. The package
  # defaults to dmenu; this pins it to rofi, which already picks up the
  # bellotto theme above. Its "Edit connections…" entry still opens
  # nm-connection-editor (hence networkmanagerapplet stays installed).
  xdg.configFile."networkmanager-dmenu/config.ini".text = ''
    [dmenu]
    dmenu_command = rofi
  '';
}
