################################################################################
#  Two runtime switchers: a palette switcher and a wallpaper switcher.
#
#  PALETTE (`theme-switch` / `palette-apply`)
#  ------------------------------------------
#  rofi menu of Omarchy-style palettes (Catppuccin Mocha, Tokyo Night, ...).
#  Applies the chosen palette live: waybar CSS re-reads its @import,
#  Hyprland borders get the new colours via hyprctl, rofi re-launches against
#  the new .rasi. Declarative consumers (hyprlock, the greeter, swaync,
#  swayosd) keep the build-time default palette and follow a rebuild.
#
#  WALLPAPER (`wallpaper-switch` / `wallpaper-apply`)
#  --------------------------------------------------
#  Separate rofi menu of the wallpapers in ./wallpapers/. Switches the
#  hyprpaper image live; the palette is unaffected.
#
#  Both apply scripts are wired into Hyprland `exec` (not `exec-once`) so
#  every config reload re-applies the saved state over the declarative
#  defaults — same pattern as lidSync in ../shortcuts.nix.
#
#  STATE FILES
#  -----------
#  ~/.config/theme/palette   — palette name (default: mocha)
#  ~/.config/theme/wallpaper  — image path (default: esplechin)
################################################################################
{ pkgs, lib, config, ... }:

let
  inherit (import ../../theme.nix { }) palettes;
  homeDir = config.home.homeDirectory;

  wallpapers = {
    esplechin = ../../wallpapers/wallpaperPaintingStyleEsplechin.png;
    bellotto  = ../../wallpapers/pirna-bellotto.jpg;
  };

  # Pretty display names keyed by attrset key; used in both rofi menus and the
  # state-file round-trip so the menu and the state can stay in lockstep.
  paletteNames = {
    mocha       = "Catppuccin Mocha";
    tokyo-night = "Tokyo Night";
  };
  wallpaperNames = {
    esplechin = "Esplechin (oil painting)";
    bellotto  = "Pirna Bellotto";
  };

  # GTK-CSS @define-color lines, one per palette role. bar.nix imports this
  # file from its stylesheet; swayosd imports it via an absolute URL (see
  # bar.nix — it lives in the nix store, hence the absolute path).
  paletteCss = raw:
    lib.concatStrings (
      lib.mapAttrsToList (name: hex: "@define-color ${name} #${hex};\n") raw
    );

  # Per-palette rofi theme; parameterised from the same raw role names the
  # GTK palette uses, so the launcher matches whatever is active.
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

  # Border-colour values: kept out of the GTK palette file because hyprland
  # expects `rgba(rrggbbaa)` strings on the command line.
  themeVars = name: ''
    SKY=${palettes.${name}.raw.sky}
    OCHRE=${palettes.${name}.raw.ochre}
    OVERLAY=${palettes.${name}.raw.overlay}
  '';

  templates = lib.mapAttrs (name: _: {
    "theme/${name}/palette.css".text = paletteCss palettes.${name}.raw;
    "theme/${name}/rofi.rasi".text   = rofiRasi palettes.${name}.raw;
    "theme/${name}/vars".text        = themeVars name;
  }) palettes;

  knownPalettes   = lib.concatStringsSep "|" (lib.attrNames palettes);
  knownWallpapers = lib.concatStringsSep "|" (lib.attrNames wallpapers);
  defaultPalette   = "mocha";
  defaultWallpaper = "esplechin";

  #### Palette apply ##########################################################
  paletteApply = pkgs.writeShellScript "palette-apply" ''
    set -eu
    name=$(cat "$HOME/.config/theme/palette" 2>/dev/null || true)
    case "$name" in
      ${knownPalettes}) ;;
      *) name=${defaultPalette} ;;
    esac

    src="$HOME/.local/share/theme/$name"
    mkdir -p "$HOME/.config/theme"
    cp "$src/palette.css" "$HOME/.config/theme/palette.css"
    cp "$src/rofi.rasi"   "$HOME/.config/theme/rofi.rasi"

    . "$src/vars"
    ${pkgs.hyprland}/bin/hyprctl keyword general:col.active_border \
      "rgba(''${SKY}ee) rgba(''${OCHRE}ee) 45deg" >/dev/null
    ${pkgs.hyprland}/bin/hyprctl keyword general:col.inactive_border \
      "rgba(''${OVERLAY}aa)" >/dev/null

    # waybar re-reads its CSS on SIGUSR2.
    killall -SIGUSR2 waybar 2>/dev/null || true
  '';

  #### Wallpaper apply ########################################################
  wallpaperApply = pkgs.writeShellScript "wallpaper-apply" ''
    set -eu
    name=$(cat "$HOME/.config/theme/wallpaper" 2>/dev/null || true)
    case "$name" in
      ${knownWallpapers}) ;;
      *) name=${defaultWallpaper} ;;
    esac

    # The path is the palette's wallpapers.<name> entry: written to the state
    # file by the switcher after the user picked it.
    img=$(cat "$HOME/.config/theme/wallpaper-path" 2>/dev/null || true)
    if [ -z "$img" ]; then
      img="${wallpapers.${defaultWallpaper}}"
    fi

    # The IPC socket may not be up at session start — short retry loop.
    for _ in $(${pkgs.coreutils}/bin/seq 1 20); do
      ${pkgs.hyprland}/bin/hyprctl hyprpaper preload "$img" >/dev/null 2>&1 && break
      ${pkgs.coreutils}/bin/sleep 0.25
    done
    ${pkgs.hyprland}/bin/hyprctl hyprpaper wallpaper ",$img" >/dev/null

    # Drop whichever image is no longer on screen to free its VRAM.
    for other in ${lib.concatStringsSep " " (lib.attrValues wallpapers)}; do
      if [ "$other" != "$img" ]; then
        ${pkgs.hyprland}/bin/hyprctl hyprpaper unload "$other" >/dev/null 2>&1 || true
      fi
    done
  '';

  #### Palette switcher #######################################################
  paletteSwitch = pkgs.writeShellScriptBin "theme-switch" ''
    set -eu
    choice=$(printf '%s\n' ${lib.concatStringsSep " " (lib.mapAttrsToList (k: v: "\"${v}\"") paletteNames)} \
      | ${pkgs.rofi}/bin/rofi -dmenu -i -p Palette \
          -theme "$HOME/.config/theme/rofi.rasi") || exit 0
    name=""
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "    [ \"${v}\" = \"$choice\" ] && name=${k}") paletteNames)}
    [ -z "$name" ] && exit 0
    mkdir -p "$HOME/.config/theme"
    printf '%s' "$name" > "$HOME/.config/theme/palette"
    ${paletteApply}
  '';

  #### Wallpaper switcher ####################################################
  wallpaperSwitch = pkgs.writeShellScriptBin "wallpaper-switch" ''
    set -eu
    choice=$(printf '%s\n' ${lib.concatStringsSep " " (lib.mapAttrsToList (k: v: "\"${v}\"") wallpaperNames)} \
      | ${pkgs.rofi}/bin/rofi -dmenu -i -p Wallpaper \
          -theme "$HOME/.config/theme/rofi.rasi") || exit 0
    name=""
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "    [ \"${v}\" = \"$choice\" ] && name=${k}") wallpaperNames)}
    [ -z "$name" ] && exit 0
    mkdir -p "$HOME/.config/theme"
    printf '%s' "$name" > "$HOME/.config/theme/wallpaper"
    case "$name" in
      esplechin) printf '%s' "${wallpapers.esplechin}" > "$HOME/.config/theme/wallpaper-path" ;;
      bellotto)  printf '%s' "${wallpapers.bellotto}"  > "$HOME/.config/theme/wallpaper-path" ;;
    esac
    ${wallpaperApply}
  '';
in
{
  home.packages = [ paletteSwitch wallpaperSwitch ];

  xdg.dataFile = lib.foldl' (a: b: a // b) { } (lib.attrValues templates);

  # Both apply scripts in exec (not exec-once): they must run on every
  # Hyprland config reload, so a rebuild does not re-assert the declarative
  # default over the user's saved theme.
  wayland.windowManager.hyprland.settings.exec = [
    "${paletteApply}"
    "${wallpaperApply}"
  ];
}
