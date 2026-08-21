################################################################################
#  Runtime theme switcher: pick a palette from rofi, get wallpaper, Hyprland
#  borders, rofi itself and waybar recoloured live. The choice persists in
#  ~/.config/theme/active and is re-applied at every session start and every
#  `rebuild` (see the exec note below), so the declarative defaults only win
#  until the script has run once.
#
#  WHAT FOLLOWS A SWITCH
#  ---------------------
#    wallpaper        hyprpaper IPC (preload/wallpaper/unload)
#    window borders   hyprctl keyword, same values wm.nix sets declaratively
#    rofi             ~/.config/theme/rofi.rasi, read fresh on each launch
#    waybar           SIGUSR2 makes it re-read its CSS; the CSS @imports
#                     ~/.config/theme/palette.css (see bar.nix)
#
#  CEILING — not worth runtime-swapping: hyprlock and the greeter are
#  declarative configs baked from the build-time default palette in
#  ../theme.nix; swayosd likewise. The waybar python helper scripts embed
#  static hex for the same reason.
################################################################################
{ pkgs, lib, config, ... }:

let
  inherit (import ../../theme.nix { }) palettes;
  homeDir = config.home.homeDirectory;

  # One image per palette. Referencing the paths here lands them in the nix
  # store automatically when interpolated into the scripts/templates below.
  wallpapers = {
    esplechin = ../../wallpapers/wallpaperPaintingStyleEsplechin.png;
    bellotto = ../../wallpapers/pirna-bellotto.jpg;
  };

  # GTK-CSS colour definitions; bar.nix's stylesheet imports this file.
  paletteCss = raw:
    lib.concatStrings (
      lib.mapAttrsToList (name: hex: "@define-color ${name} #${hex};\n") raw
    );

  # Parameterised version of the rofi theme that used to live in launcher.nix.
  rofiRasi = raw: ''
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

  # Shell fragment the apply script sources: only the values that cannot be
  # copied as files — border colours and the store path of the wallpaper.
  themeVars = name: ''
    SKY=${palettes.${name}.raw.sky}
    OCHRE=${palettes.${name}.raw.ochre}
    OVERLAY=${palettes.${name}.raw.overlay}
    WALLPAPER="${wallpapers.${name}}"
  '';

  templates = lib.mapAttrs (name: _: {
    "theme/${name}/palette.css".text = paletteCss palettes.${name}.raw;
    "theme/${name}/rofi.rasi".text = rofiRasi palettes.${name}.raw;
    "theme/${name}/vars".text = themeVars name;
  }) palettes;

  # Valid names for the state-file check below, straight from the attrset.
  knownNames = lib.concatStringsSep "|" (lib.attrNames palettes);

  #### Apply ###################################################################
  # Copies the chosen palette into ~/.config/theme/ and pokes every live
  # consumer. Safe to run any time; also the boot/reload entry point.
  applyTheme = pkgs.writeShellScript "theme-apply" ''
    set -eu
    PATH=${lib.makeBinPath [ pkgs.hyprland pkgs.coreutils pkgs.procps ]}

    name=$(cat "$HOME/.config/theme/active" 2>/dev/null || true)
    case "$name" in
      ${knownNames}) ;;
      *) name=esplechin ;;
    esac

    src="$HOME/.local/share/theme/$name"
    mkdir -p "$HOME/.config/theme"
    cp "$src/palette.css" "$HOME/.config/theme/palette.css"
    cp "$src/rofi.rasi"   "$HOME/.config/theme/rofi.rasi"

    . "$src/vars"

    # Borders: same gradient wm.nix sets declaratively.
    ${pkgs.hyprland}/bin/hyprctl keyword general:col.active_border \
      "rgba(''${SKY}ee) rgba(''${OCHRE}ee) 45deg" >/dev/null
    ${pkgs.hyprland}/bin/hyprctl keyword general:col.inactive_border \
      "rgba(''${OVERLAY}aa)" >/dev/null

    # Wallpaper over the hyprpaper IPC socket. At session start this script
    # can beat hyprpaper to the socket, hence the short retry loop.
    for _ in $(${pkgs.coreutils}/bin/seq 1 20); do
      ${pkgs.hyprland}/bin/hyprctl hyprpaper preload "$WALLPAPER" >/dev/null 2>&1 && break
      ${pkgs.coreutils}/bin/sleep 0.25
    done
    ${pkgs.hyprland}/bin/hyprctl hyprpaper wallpaper ",$WALLPAPER" >/dev/null

    # Free the VRAM of whichever image is no longer shown.
    for img in ${wallpapers.esplechin} ${wallpapers.bellotto}; do
      if [ "$img" != "$WALLPAPER" ]; then
        ${pkgs.hyprland}/bin/hyprctl hyprpaper unload "$img" >/dev/null 2>&1 || true
      fi
    done

    printf '%s' "$WALLPAPER" > "$HOME/.config/theme/wallpaper"

    # waybar re-reads its CSS on SIGUSR2 (its own reload signal).
    killall -SIGUSR2 waybar 2>/dev/null || true
  '';

  #### Switcher ##############################################################
  # rofi dmenu -> write state -> apply. Rofi reads the runtime theme via
  # -theme, so the menu itself already shows the current palette.
  switchTheme = pkgs.writeShellScriptBin "theme-switch" ''
    set -eu
    choice=$(printf 'Esplechin\nPirna Bellotto' \
      | ${pkgs.rofi}/bin/rofi -dmenu -i -p Theme -theme "$HOME/.config/theme/rofi.rasi") || exit 0
    case "$choice" in
      "Esplechin")     name=esplechin ;;
      "Pirna Bellotto") name=bellotto ;;
      *) exit 0 ;;
    esac
    mkdir -p "$HOME/.config/theme"
    printf '%s' "$name" > "$HOME/.config/theme/active"
    ${applyTheme}
  '';
in
{
  home.packages = [ switchTheme ];

  xdg.dataFile = lib.foldl' (a: b: a // b) { } (lib.attrValues templates);

  # Plain `exec`, not exec-once: like lidSync in ../shortcuts.nix, it must run
  # again on every Hyprland config reload — a rebuild repoints the config,
  # Hyprland re-applies the declarative (default-palette) borders and
  # wallpaper, and this reconciles the saved theme back over them.
  wayland.windowManager.hyprland.settings.exec = [ "${applyTheme}" ];
}
