################################################################################
#  Kleurpalet — één bron voor waybar, mako, swayosd, rofi, hyprlock, de
#  vensterranden van Hyprland én het loginscherm. Verander een kleur hier en
#  alles volgt mee; dat is precies waarom dit een apart bestand is, net als
#  ./wallpaper.nix.
#
#  DE KLEUREN ZIJN NIET VERZONNEN
#  ------------------------------
#  Ze zijn met imagemagick uit de wallpaper zelf bemonsterd
#  (./wallpapers/pirna-bellotto.jpg — Bernardo Bellotto, "Pirna vanaf
#  Sonnenstein"), per gebied van het doek:
#
#      ink/base/surface  donkere voorgrond en boomschaduw onderaan
#      sky / haze        de lucht en de nevel boven de horizon
#      stone / ochre     zonbeschenen kalksteen en de gouden velden
#      terra / ember     de dakpannen van stad en kasteel
#      meadow            de zonbeschenen weide rechts
#
#  Alleen `alarm` is bijgewerkt: dat is het dakpannenrood, iets verzadigder
#  gezet omdat de originele tint op een donkere achtergrond te weinig
#  "let op!" schreeuwt.
#
#  FORMATEN
#  --------
#  Elk programma wil de kleur anders geschreven hebben, dus staan de cijfers
#  hier kaal (`raw`, zonder #) en met hekje (`css`):
#
#      waybar / swayosd (GTK-CSS)  ${css.sky}            -> #a5d0cb
#                                  alpha(${css.ink}, .9) -> GTK's eigen functie
#      mako                        "#${raw.ink}e6"       -> #rrggbbaa
#      rofi (.rasi)                #${raw.sky}ff         -> #rrggbbaa
#      hyprlock / hyprland         rgb(${raw.sky})       -> rgb(a5d0cb)
#                                  rgba(${raw.ink}cc)    -> rgba(rrggbbaa)
################################################################################
{ }:

let
  raw = {
    ink = "0d1210"; # diepste schaduw, voorgrond onderaan het doek
    base = "141a16"; # achtergrondvlak (balk, popups)
    surface = "1d241b"; # iets lichter vlak: hover, kaarten
    overlay = "2a3327"; # niet-gevulde voortgangsbalken, scheidingslijnen
    muted = "5b6a56"; # uitgeschakelde tekst
    subtle = "8e9c8a"; # secundaire tekst (inactieve workspace, venseltitel)
    text = "dce4d6"; # hoofdtekst

    sky = "a5d0cb"; # hemel — primair accent
    haze = "8ab4b0"; # nevel aan de horizon — accent, doffer
    stone = "cec88a"; # zonbeschenen kalksteen — licht accent
    ochre = "b99d55"; # gouden velden — waarschuwing
    terra = "b7713b"; # dakpannen, verlicht
    ember = "9e5c2e"; # dakpannen, in de schaduw
    meadow = "93943f"; # zonbeschenen weide — "alles in orde"
    alarm = "c0512c"; # dakrood, verzadigder — kritiek
  };
in
{
  inherit raw;

  # Zelfde waarden, klaar voor CSS-bestanden.
  css = builtins.mapAttrs (_: v: "#${v}") raw;
}
