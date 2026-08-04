################################################################################
#  Desktop packages (only the WM/Wayland stack).
################################################################################
{ pkgs, lib, config, ... }:
{
  #### Desktop packages (only the WM/Wayland stack) ##########################
  home.packages = with pkgs; [
    # waybar comes from programs.waybar (bottom of this file), not from here.
    wofi                   # second launcher (dmenu mode for cliphist)
    # rofi is deliberately NOT listed here: it comes from programs.rofi (bottom
    # of this file) with its own theme. Listing it here as well causes a
    # file collision in home-manager — both want bin/rofi in the same profile.
    libnotify              # notify-send (mako itself comes from services.mako)
    hyprlock               # screen locker
    grim slurp swappy      # screenshots (+ annotate)
    wl-clipboard cliphist  # clipboard + history
    brightnessctl playerctl pamixer pavucontrol
    ddcutil                # DDC/CI over i2c — only works on a DIRECT cable, not
                           # through the dock; see the note at brightnessExternal
    wl-gammarelay-rs       # external screen brightness via the gamma ramp
    networkmanagerapplet    # provides nm-connection-editor, used by the Wi-Fi picker's "Edit connections…"
    networkmanager_dmenu    # Wi-Fi picker for the waybar `network` module
    # blueman comes from services.blueman.enable in ../configuration.nix, so
    # the GUI and its system service (blueman-mechanism) share one version.
    nautilus xfce.thunar   # file managers (GTK)
    udiskie                # auto-mounts USB drives on plug-in; status is the custom/disks waybar module
    nwg-look               # GTK theme settings
    papirus-icon-theme     # icons for rofi's app list (icon-theme below)
    polkit_gnome           # auth agent
    viewnior               # image viewer: arrows scroll through the folder's
                           # images out of the box, no config needed
  ];

  # Open images in the viewer, not the browser (browser can't page through a folder).
  xdg.mimeApps.defaultApplications = {
    "image/jpeg" = "viewnior.desktop";
    "image/png" = "viewnior.desktop";
    "image/gif" = "viewnior.desktop";
    "image/webp" = "viewnior.desktop";
    "image/bmp" = "viewnior.desktop";
    "image/svg+xml" = "viewnior.desktop";
  };
}
