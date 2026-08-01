################################################################################
#  home-manager entry for user ogryson.
#  Config is split across ./home/*.nix — this file only wires them together.
################################################################################
{ ... }:
{
  imports = [
    ./home/packages.nix    # apps, dev tooling, CLI/terminal tools
    ./home/programs.nix    # git, bash, kitty, shell QoL
    ./home/desktop.nix     # Hyprland + Wayland desktop (packages + config)
    ./home/shortcuts.nix   # Hyprland keyboard & mouse shortcuts
    ./home/webapps.nix     # PWA launchers (SoundCloud, Snapchat)
  ];

  home.username = "ogryson";
  home.homeDirectory = "/home/ogryson";
  home.stateVersion = "25.11";

  programs.home-manager.enable = true;
}
