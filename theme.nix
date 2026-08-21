################################################################################
#  Colour palette — one source for waybar, swaync, swayosd, rofi, hyprlock, the
#  Hyprland window borders and the login screen. Change a colour here and
#  everything follows; that is exactly why this is a separate file, like
#  ./wallpaper.nix.
#
#  THE COLOURS ARE SAMPLED, NOT INVENTED
#  -------------------------------------
#  Each palette was pulled out of its wallpaper with imagemagick, per region
#  of the canvas, then mapped onto shared semantic role names so every
#  consumer can switch palette without knowing which painting it came from:
#
#      magick wallpapers/<image> -resize 200x -colors 16 -unique-colors txt:
#
#  Roles (same meaning in every palette):
#      ink/base/surface/overlay  backgrounds, darkest to lightest
#      muted/subtle/text         disabled, secondary and body text
#      sky / haze                primary accent, and a duller variant
#      stone / ochre             light highlight, and warning
#      terra / ember             warm mid accent, and its darker shade
#      meadow                    success ("all is well")
#      alarm                     critical
#
#  bellotto — ./wallpapers/pirna-bellotto.jpg (Bernardo Bellotto, "Pirna seen
#  from Sonnenstein"):
#      ink/base/surface  dark foreground and tree shadow at the bottom
#      sky / haze        the sky and the haze above the horizon
#      stone / ochre     sunlit limestone and the golden fields
#      terra / ember     the roof tiles of the town and the castle
#      meadow            the sunlit meadow on the right
#  Only `alarm` was adjusted: that is the roof-tile red, pushed a bit more
#  saturated because the original tint does not shout "look here!" loudly
#  enough on a dark background.
#
#  esplechin — ./wallpapers/wallpaperPaintingStyleEsplechin.png:
#      ink/base/surface  the dark olive foreground mass
#      sky / haze        the slate-grey blue of the distant water/sky band,
#                        the only cool tones in an otherwise olive canvas
#      stone / ochre     pale sand highlights and the lighter earth
#      terra / ember     golden-brown architecture, lit and shaded
#      meadow            the brighter olive-green fields
#  Swatches the 16-colour quantizer skipped were interpolated between
#  neighbours (base/surface/muted), and `alarm` does not exist in this
#  painting at all — it is a rust red chosen to sit in the canvas's warm
#  range while still reading as critical on the dark backgrounds.
#
#  FORMATS
#  -------
#  Every program wants the colour written differently, so the numbers live here
#  bare (`raw`, no #) and with a hash (`css`):
#
#      waybar / swayosd (GTK CSS)  ${css.sky}            -> #a5d0cb
#                                  alpha(${css.ink}, .9) -> GTK's own function
#      GTK CSS w/ alpha            "#${raw.ink}e6"       -> #rrggbbaa
#      rofi (.rasi)                #${raw.sky}ff         -> #rrggbbaa
#      hyprlock / hyprland         rgb(${raw.sky})       -> rgb(a5d0cb)
#                                  rgba(${raw.ink}cc)    -> rgba(rrggbbaa)
#
#  RUNTIME SWITCHING
#  -----------------
#  The top-level `raw`/`css` are the DEFAULT palette (esplechin — it matches
#  the wallpaper that hyprpaper loads). Declarative configs baked from them
#  (hyprlock, the greeter, swayosd) keep that default even after a runtime
#  switch; see ./home/desktop/theme-switch.nix for what follows the switch
#  live. All palettes are available under `palettes`.
################################################################################
{ }:

let
  bellottoRaw = {
    ink = "0d1210"; # deepest shadow, foreground at the bottom of the canvas
    base = "141a16"; # background surface (bar, popups)
    surface = "1d241b"; # slightly lighter surface: hover, cards
    overlay = "2a3327"; # unfilled progress bars, separators
    muted = "5b6a56"; # disabled text
    subtle = "8e9c8a"; # secondary text (inactive workspace, window title)
    text = "dce4d6"; # body text

    sky = "a5d0cb"; # sky — primary accent
    haze = "8ab4b0"; # haze on the horizon — accent, duller
    stone = "cec88a"; # sunlit limestone — light accent
    ochre = "b99d55"; # golden fields — warning
    terra = "b7713b"; # roof tiles, lit
    ember = "9e5c2e"; # roof tiles, in shadow
    meadow = "93943f"; # sunlit meadow — "all is well"
    alarm = "c0512c"; # roof red, more saturated — critical
  };

  esplechinRaw = {
    ink = "222217"; # deepest olive shadow
    base = "2b2818"; # foreground mass, eased off the quantizer yellow
    surface = "3d371f"; # hover, cards
    overlay = "504c18"; # unfilled progress bars, separators
    muted = "6b643c"; # disabled text
    subtle = "90978f"; # secondary text
    text = "dec58d"; # palest sand — body text

    sky = "788a8e"; # slate-blue water/sky band — primary accent
    haze = "6b7e84"; # duller accent
    stone = "cbb88b"; # pale sand highlight
    ochre = "a49161"; # lighter earth — warning
    terra = "8c7034"; # golden-brown architecture, lit
    ember = "675922"; # architecture, in shadow
    meadow = "70682a"; # bright olive fields — "all is well"
    alarm = "b0512a"; # rust red, invented (see header) — critical
  };

  mkPalette = raw: {
    inherit raw;
    # Same values, ready for CSS files.
    css = builtins.mapAttrs (_: v: "#${v}") raw;
  };
in

# Default = esplechin: it matches the wallpaper that ships active. Spread so
# every existing consumer reading `raw`/`css` off the top level keeps working.
(mkPalette esplechinRaw)
// {
  palettes = {
    bellotto = mkPalette bellottoRaw;
    esplechin = mkPalette esplechinRaw;
  };
}
