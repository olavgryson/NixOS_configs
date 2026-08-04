################################################################################
#  One wallpaper for the login screen (greetd/ReGreet + hyprpaper), the desktop
#  (hyprpaper) and the lock screen (hyprlock). Imported by ./greeter.nix and
#  ./home/desktop.nix, so all three are guaranteed to show the same image.
#
#  The matching colours live in ./theme.nix — they were sampled from THIS
#  image. Swap the wallpaper and you should resample that file too.
#
#  USING YOUR OWN WALLPAPER
#  ------------------------
#  Put the image in ./wallpapers/ and `git add` it — otherwise the flake does
#  not see it, since flakes only copy tracked files into the store — then point
#  `src` below at it.
#
#  Important: the path has to end up in the nix store, because the login screen
#  runs as user `greeter` and cannot read anything under /home/ogryson.
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
