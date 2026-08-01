################################################################################
#  Eén wallpaper voor loginscherm (greetd/ReGreet + hyprpaper), desktop
#  (hyprpaper) en lockscherm (hyprlock). Geïmporteerd door ./greeter.nix en
#  ./home/desktop.nix, zodat alle drie gegarandeerd dezelfde afbeelding tonen.
#
#  De bijbehorende kleuren staan in ./theme.nix — die zijn uit déze afbeelding
#  bemonsterd. Wissel je de wallpaper, herbemonster dan ook dat bestand.
#
#  EIGEN WALLPAPER GEBRUIKEN
#  -------------------------
#  Zet je afbeelding in ./wallpapers/ en git add hem — anders ziet de flake hem
#  niet, want flakes kopiëren alleen getrackte bestanden naar de store — en pas
#  `src` hieronder aan.
#
#  Belangrijk: het pad moet in de nix-store belanden, want het loginscherm
#  draait als gebruiker `greeter` en kan niets in /home/ogryson lezen.
#
#  ONE SIZE PER SCREEN
#  -------------------
#  `width`/`height` are arguments now. Reason: this was always baked at 1920x1280,
#  so on the 3440x1440 ultrawide hyprpaper had to blow that small image up 1.8x to
#  "cover" it — which is why the wallpaper looked zoomed in and blurry there. Every
#  resolution now gets its own render straight from the 4421x2500 source. The
#  defaults are the laptop panel, so existing callers
#  (`import ./wallpaper.nix { inherit pkgs; }`) keep doing what they did.
################################################################################
{ pkgs, width ? 1920, height ? 1280 }:

pkgs.runCommand "wallpaper-${toString width}x${toString height}.png"
  {
    nativeBuildInputs = [ pkgs.imagemagick ];
    src = ./wallpapers/wallpaperPaintingStyleEsplechin.png;
  }
  ''
    # The source is 4421x2500 (7:4) and fits no screen exactly. That difference
    # has to go somewhere:
    #   -resize ...^   scales until the SHORTEST side fits (so no black bars)
    #   -extent        trims the excess symmetrically
    # Together that is "cover", not stretch.
    #
    # At 1920x1280 (3:2) about 8% is lost left and right. At 3440x1440 (21:9) it is
    # the other way round: the width fits and roughly 26% comes off top and bottom
    # combined. The town and the castle sit on the middle band and stay in frame.
    #
    # Scaled once at build time instead of making hyprpaper shrink 11 megapixels on
    # every boot — saves VRAM and a slow first frame.
    magick "$src" \
      -resize ${toString width}x${toString height}^ \
      -gravity center -extent ${toString width}x${toString height} \
      -depth 8 -define png:color-type=2 \
      $out
  ''
