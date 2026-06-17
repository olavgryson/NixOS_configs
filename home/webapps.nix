################################################################################
#  Web apps (PWAs) — recreated declaratively as browser --app launchers.
#  These were Chromium/Brave "installed web apps" on your Debian box; here they
#  become proper .desktop entries that show up in wofi.
#  Swap `brave` for `chromium` if you prefer; --app gives the chromeless window.
################################################################################
{ pkgs, ... }:
let
  webapp = name: url: {
    inherit name;
    genericName = "Web App";
    exec = "${pkgs.brave}/bin/brave --app=${url}";
    terminal = false;
    categories = [ "Network" ];
  };
in
{
  xdg.desktopEntries = {
    soundcloud = webapp "SoundCloud" "https://soundcloud.com/discover";
    snapchat   = webapp "Snapchat"   "https://www.snapchat.com/web";
  };
}
