################################################################################
#  Configured programs — git, bash, terminal, shell QoL.
################################################################################
{ pkgs, ... }:
{
  #### Git (from current global config) #######################################
  programs.git = {
    enable = true;
    userName = "Olav Gryson";
    userEmail = "olav.gryson@gmail.com";
    extraConfig.init.defaultBranch = "main";
  };

  #### Shell (keeps bash, adds modern helpers) ################################
  programs.bash = {
    enable = true;
    shellAliases = {
      ll = "eza -la --git";
      cat = "bat -pp";
      rebuild = "sudo nixos-rebuild switch --flake ~/nixos-config#dragonflyg4";
    };
  };
  programs.zoxide.enable = true;
  programs.fzf.enable = true;

  #### Terminal (provides the kitty package too) #############################
  programs.kitty = {
    enable = true;
    settings = {
      font_family = "JetBrainsMono Nerd Font";
      font_size = 12;
      background_opacity = "0.95";
    };
  };
}
