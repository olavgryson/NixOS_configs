################################################################################
#  Colour palette — one source for waybar, swaync, swayosd, rofi, hyprlock, the
#  Hyprland window borders and the login screen. Change a hex here and the whole
#  desktop follows; that is why this file is separate, like ./wallpaper.nix.
#
#  THE PALETTES
#  ------------
#  Two built-in palettes, both standard dark, single-accent schemes chosen to
#  match the Omarchy 4.0 aesthetic (clean modern, lots of contrast, not the
#  earth-tone painting look the previous bellotto sample produced). Names and
#  hex values are the canonical published palettes — no resampling, no
#  inventing.
#
#      mocha        — Catppuccin Mocha: warm dark base, soft pastel accents
#      tokyo-night  — Tokyo Night: cooler dark base, single neon-blue accent
#
#  ROLES (same meaning in every palette, so consumers can swap freely):
#      ink/base/surface/overlay   backgrounds, darkest to lightest
#      muted/subtle/text          disabled, secondary and body text
#      sky / haze                 primary accent, and a duller variant
#      stone / ochre              light highlight, and warning
#      terra / ember              warm mid accent, and its darker shade
#      meadow                     success ("all is well")
#      alarm                      critical
#
#  FORMATS
#  -------
#  Every program wants the colour written differently, so the numbers live here
#  bare (`raw`, no #) and with a hash (`css`):
#
#      waybar / swayosd (GTK CSS)  ${css.sky}            -> #89b4fa
#                                  alpha(@sky, .9)       -> GTK's own function
#      rofi (.rasi)                #${raw.sky}ff         -> #rrggbbaa
#      hyprlock / hyprland         rgb(${raw.sky})       -> rgb(89b4fa)
#                                  rgba(${raw.ink}cc)    -> rgba(rrggbbaa)
#
#  RUNTIME SWITCHING
#  -----------------
#  The top-level `raw`/`css` are the DEFAULT palette (mocha) — the same value
#  declarative configs (hyprlock, the greeter, swaync, swayosd) get baked with
#  at build time. Live-switchable consumers (waybar via @define-color import,
#  Hyprland borders via hyprctl, rofi via runtime .rasi copy) follow a
#  runtime switch through the script in ./home/desktop/theme-switch.nix.
################################################################################
{ }:

let
  mochaRaw = {
    ink     = "11111b"; # crust
    base    = "1e1e2e"; # base
    surface = "313244"; # surface0
    overlay = "45475a"; # surface1
    muted   = "6c7086"; # overlay0
    subtle  = "a6adc8"; # subtext0
    text    = "cdd6f4"; # text

    sky   = "89b4fa"; # blue — primary accent
    haze  = "b4befe"; # lavender — accent, duller
    stone = "f9e2af"; # yellow — light highlight
    ochre = "fab387"; # peach — warning
    terra = "eba0ac"; # maroon — warm mid
    ember = "f38ba8"; # red — warm darker
    meadow = "a6e3a1"; # green — success
    alarm  = "f38ba8"; # red — critical
  };

  tokyoNightRaw = {
    ink     = "16161e"; # one shade deeper than background
    base    = "1a1b26"; # background
    surface = "24283b"; # background alt
    overlay = "414868"; # terminal black
    muted   = "565f89"; # comment
    subtle  = "787c99"; # comment alt
    text    = "c0caf5"; # foreground

    sky   = "7aa2f7"; # blue — primary accent
    haze  = "bb9af7"; # purple — accent, duller
    stone = "e0af68"; # yellow — light highlight
    ochre = "ff9e64"; # orange — warning
    terra = "f7768e"; # magenta — warm mid
    ember = "ff757f"; # red — warm darker
    meadow = "9ece6a"; # green — success
    alarm  = "ff757f"; # red — critical
  };

  mkPalette = raw: {
    inherit raw;
    css = builtins.mapAttrs (_: v: "#${v}") raw;
  };
in

# Default = mocha: the warmer, softer Omarchy default. Spread so every existing
# consumer reading `raw`/`css` off the top level keeps working unchanged.
(mkPalette mochaRaw)
// {
  palettes = {
    mocha       = mkPalette mochaRaw;
    tokyo-night = mkPalette tokyoNightRaw;
  };
}
