################################################################################
#  Display + wallpaper definitions - ONE source used by Hyprland, hyprpaper,
#  hyprlock and the shortcuts file.  Change a screen or the wallpaper here and
#  everything that follows.  Rendering logic lives in ../wallpaper.nix.
################################################################################
{ pkgs }:

let
  # Same image the login screen (../greeter.nix) uses, but rendered per screen
  # size — see the explanation in ../wallpaper.nix. `wallpaper` stays the laptop
  # version because hyprlock uses it too.
  wallpaper = import ../../wallpaper.nix { inherit pkgs; };
  wallpaperUltrawide = import ../../wallpaper.nix {
    inherit pkgs;
    width = 3440;
    height = 1440;
  };

  # The external monitor's connector name is NOT stable: the USB-C dock speaks
  # DisplayPort MST, and the kernel reassigns the invented name on every replug
  # (it has been DP-6 and DP-7). Match by EDID description instead, which stays
  # the same, so monitor placement and the per-screen wallpaper keep working no
  # matter what the connector happens to be called today. Both Hyprland monitor
  # rules and hyprpaper accept `desc:<description>`.
  externalMonitorDesc = "desc:Xiaomi Corporation Mi Monitor";
in
{
  inherit wallpaper wallpaperUltrawide externalMonitorDesc;

  # One place for the screen definitions, so the monitor lines below and any
  # script that re-enables a panel use the exact same string and the laptop
  # always comes back in the same spot. See the diagram at `monitor =` for
  # where 760x1440 comes from.
  laptopMonitor = "eDP-1,1920x1280@60,760x1440,1";
  externalMonitor = "${externalMonitorDesc},3440x1440@120,0x0,1";
}
