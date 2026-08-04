################################################################################
#  Web apps (PWAs) — declared as browser --app launchers, which become proper
#  .desktop entries that show up in wofi.
#  Uses Chromium (Zen/Firefox have no clean --app chromeless mode).
################################################################################
{ pkgs, ... }:
let
  webapp = name: url: icon: {
    inherit name icon;
    genericName = "Web App";
    exec = "${pkgs.chromium}/bin/chromium --app=${url}";
    terminal = false;
    categories = [ "Network" ];
  };
in
{
  xdg.desktopEntries = {
    # "soundcloud" is a theme icon name — Papirus (our icon theme) ships one.
    soundcloud = webapp "SoundCloud" "https://soundcloud.com/discover" "soundcloud";
    # No Snapchat icon in Papirus, so we ship our own (home/icons/snapchat.svg —
    # Papirus-style badge built from the MIT-licensed simple-icons glyph).
    snapchat   = webapp "Snapchat"   "https://www.snapchat.com/web" ./icons/snapchat.svg;
  };
}
