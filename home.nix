################################################################################
#  home-manager entry for user ogryson.
#  Config is split across ./home/*.nix — this file only wires them together.
################################################################################
{ ... }:
{
  imports = [
    ./home/packages.nix    # apps, dev tooling, CLI/terminal tools
    ./home/programs.nix    # git, bash, kitty, shell QoL
    ./home/desktop/packages.nix     # desktop packages
    ./home/desktop/bar.nix          # waybar + OSD + helper scripts
    ./home/desktop/look.nix         # cursor + GTK
    ./home/desktop/notifications.nix # mako
    ./home/desktop/launcher.nix     # rofi + Wi-Fi picker
    ./home/desktop/daemons.nix      # battery + display-gamma services
    ./home/desktop/screen.nix       # hypridle + hyprlock + hyprpaper
    ./home/desktop/wm.nix           # Hyprland compositor
    ./home/shortcuts.nix   # Hyprland keyboard & mouse shortcuts
    ./home/webapps.nix     # PWA launchers (SoundCloud, Snapchat)
  ];

  home.username = "ogryson";
  home.homeDirectory = "/home/ogryson";
  home.stateVersion = "25.11";

  programs.home-manager.enable = true;
}
