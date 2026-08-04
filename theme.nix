################################################################################
#  Colour palette — one source for waybar, mako, swayosd, rofi, hyprlock, the
#  Hyprland window borders and the login screen. Change a colour here and
#  everything follows; that is exactly why this is a separate file, like
#  ./wallpaper.nix.
#
#  THE COLOURS ARE SAMPLED, NOT INVENTED
#  -------------------------------------
#  They were pulled out of the wallpaper itself with imagemagick
#  (./wallpapers/pirna-bellotto.jpg — Bernardo Bellotto, "Pirna seen from
#  Sonnenstein"), per region of the canvas:
#
#      ink/base/surface  dark foreground and tree shadow at the bottom
#      sky / haze        the sky and the haze above the horizon
#      stone / ochre     sunlit limestone and the golden fields
#      terra / ember     the roof tiles of the town and the castle
#      meadow            the sunlit meadow on the right
#
#  Only `alarm` was adjusted: that is the roof-tile red, pushed a bit more
#  saturated because the original tint does not shout "look here!" loudly
#  enough on a dark background.
#
#  To resample after a wallpaper change:
#      magick wallpapers/<image> -resize 200x -colors 16 -unique-colors txt:
#
#  FORMATS
#  -------
#  Every program wants the colour written differently, so the numbers live here
#  bare (`raw`, no #) and with a hash (`css`):
#
#      waybar / swayosd (GTK CSS)  ${css.sky}            -> #a5d0cb
#                                  alpha(${css.ink}, .9) -> GTK's own function
#      mako                        "#${raw.ink}e6"       -> #rrggbbaa
#      rofi (.rasi)                #${raw.sky}ff         -> #rrggbbaa
#      hyprlock / hyprland         rgb(${raw.sky})       -> rgb(a5d0cb)
#                                  rgba(${raw.ink}cc)    -> rgba(rrggbbaa)
################################################################################
{ }:

let
  raw = {
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
in
{
  inherit raw;

  # Same values, ready for CSS files.
  css = builtins.mapAttrs (_: v: "#${v}") raw;
}
